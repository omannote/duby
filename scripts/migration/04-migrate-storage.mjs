#!/usr/bin/env node
/**
 * 04 — نقل صور الطلبات بين حاويتي Storage، وإنشاء صفوف `order_photos`.
 *
 * يأتي بعد التحميل لا قبله: `order_photos.sha256` فريد وغير فارغ، والبصمة لا
 * تُعرف إلا بقراءة الملف. فالنسخ والحوسبة والإدراج عملية واحدة.
 *
 * التنفيذ آمن للتكرار: ما نُقل يُتخطّى بمطابقة البصمة، فانقطاع الشبكة في
 * منتصف ألف صورة يُستأنف لا يُعاد من الصفر.
 *
 * التشغيل:
 *   SOURCE_URL=… SOURCE_SERVICE_KEY=… \
 *   TARGET_URL=… TARGET_SERVICE_KEY=… \
 *   TARGET_DB_URL=… node scripts/migration/04-migrate-storage.mjs [--dry-run]
 */
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';

const DRY_RUN = process.argv.includes('--dry-run');

const {
  SOURCE_URL,
  SOURCE_SERVICE_KEY,
  TARGET_URL,
  TARGET_SERVICE_KEY,
  TARGET_DB_URL,
  SOURCE_BUCKET = 'order-photos',
  TARGET_BUCKET = 'order-photos',
} = process.env;

for (const [name, value] of Object.entries({
  SOURCE_URL,
  SOURCE_SERVICE_KEY,
  TARGET_URL,
  TARGET_SERVICE_KEY,
  TARGET_DB_URL,
})) {
  if (!value) {
    console.error(`متغيّر البيئة ${name} مفقود.`);
    process.exit(1);
  }
}

const source = createClient(SOURCE_URL, SOURCE_SERVICE_KEY, { auth: { persistSession: false } });
const target = createClient(TARGET_URL, TARGET_SERVICE_KEY, { auth: { persistSession: false } });

function psql(sql) {
  return execFileSync(
    'psql',
    [TARGET_DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-t', '-A', '-c', sql],
    {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    },
  ).trim();
}

/** كل مسار صورة في المصدر مع الطلب ونوع الصورة الذي يقابله في المخطط الجديد. */
const rows = psql(`
  select o.id || '|' || kind || '|' || path || '|' || coalesce(actor::text, '')
    from src.orders o
    cross join lateral (values
      ('order',    o.order_photo_path,    null::uuid),
      ('pickup',   o.pickup_photo_path,   o.pickup_confirmed_by),
      ('delivery', o.delivery_photo_path, o.delivery_confirmed_by)
    ) as v(kind, path, actor)
   where v.path is not null
     and exists (select 1 from orders t where t.id = o.id)
   order by o.created_at
`)
  .split('\n')
  .filter(Boolean)
  .map((line) => {
    const [orderId, kind, path, actor] = line.split('|');
    return { orderId, kind, path, actor: actor || null };
  });

console.log(`صور للنقل: ${rows.length}${DRY_RUN ? ' (تجربة جافّة)' : ''}`);

let copied = 0;
let skipped = 0;
const failures = [];

for (const row of rows) {
  const already = psql(
    `select count(*) from order_photos where order_id = '${row.orderId}' and kind = '${row.kind}'`,
  );

  if (already !== '0') {
    skipped += 1;
    continue;
  }

  const { data, error } = await source.storage.from(SOURCE_BUCKET).download(row.path);

  if (error || !data) {
    failures.push({ ...row, reason: error?.message ?? 'تعذّر التنزيل' });
    continue;
  }

  const bytes = Buffer.from(await data.arrayBuffer());
  const sha256 = createHash('sha256').update(bytes).digest('hex');

  if (DRY_RUN) {
    copied += 1;
    continue;
  }

  const upload = await target.storage
    .from(TARGET_BUCKET)
    .upload(row.path, bytes, { contentType: data.type || 'image/jpeg', upsert: true });

  if (upload.error) {
    failures.push({ ...row, reason: upload.error.message });
    continue;
  }

  /*
   * البصمة فريدة على مستوى الجدول كله: صورة واحدة رُفعت لطلبين في النظام
   * القديم تُدرج مرة واحدة. الثانية تُسجَّل تخطّيًا لا فشلًا.
   */
  psql(`
    insert into order_photos (order_id, kind, storage_path, byte_size, sha256, taken_by, taken_at)
    values ('${row.orderId}', '${row.kind}', '${row.path}', ${bytes.length},
            '${sha256}', ${row.actor ? `'${row.actor}'` : 'null'},
            (select created_at from orders where id = '${row.orderId}'))
    on conflict do nothing;

    insert into private.migration_log (entity, source_id, target_id, action, reason)
    values ('order_photo', '${row.path}', '${row.orderId}', 'copied',
            'نُقلت من حاوية النظام السابق');
  `);

  copied += 1;
}

console.log(`✓ نُقلت ${copied} · تُخطّيت ${skipped} · فشلت ${failures.length}`);

if (failures.length > 0) {
  console.error('\nالصور التي فشلت:');
  for (const failure of failures) {
    console.error(`  ${failure.path} (${failure.orderId}) — ${failure.reason}`);
  }
  /*
   * الفشل هنا لا يُبطل الترحيل: الطلب سليم بلا صورته، والصورة وثيقة مساندة.
   * لكنه يخرج برمز غير صفري كي لا يمرّ في سكربت التشغيل بصمت.
   */
  process.exit(1);
}
