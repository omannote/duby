#!/usr/bin/env node
/**
 * بروفة الترحيل: الدورة كاملة على بيانات تحاكي كل حالة صعبة.
 *
 * «سكربتات الترحيل مُختبَرة» معيار قبول لا يُغلق بقراءة الشيفرة: هنا تُشغَّل
 * السكربتات نفسها التي ستعمل ليلة الإطلاق، على مخطط الهدف نفسه، ويُتحقق من
 * النتيجة صفًّا صفًّا — ثم يُتراجع ويُعاد التحميل للتأكد أن البروفة قابلة
 * للتكرار.
 *
 * تحذير: يكتب في قاعدة الهدف ويتراجع. قاعدة اختبار فقط.
 *
 * التشغيل: pnpm test:migration
 */
import { execFileSync } from 'node:child_process';

const DB_URL =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

let failures = 0;

function psql(sql) {
  return execFileSync(
    'psql',
    [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-t', '-A', '-c', sql],
    {
      encoding: 'utf8',
      maxBuffer: 32 * 1024 * 1024,
    },
  ).trim();
}

/*
 * stdout وstderr معًا: رسائل RAISE NOTICE — وهي كيف تعلن السكربتات نجاحها —
 * تخرج على stderr، فالاكتفاء بـstdout يجعل الفحص يقرأ نجاحًا غيابًا.
 */
function runFile(path) {
  return execFileSync(
    'psql',
    [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-f', path, '--no-psqlrc'],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] },
  );
}

function runFileAll(path) {
  const result = execFileSync(
    'bash',
    ['-c', `psql "$0" -v ON_ERROR_STOP=1 -X -q -f "$1" 2>&1`, DB_URL, path],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 },
  );
  return result;
}

/** يُتوقَّع منه الفشل: يعيد رسالة الخطأ، ويرمي إن نجح. */
function expectFailure(path, label) {
  try {
    runFile(path);
  } catch (error) {
    return `${error.stdout ?? ''}${error.stderr ?? ''}`;
  }
  throw new Error(`${label}: كان يُفترض أن يفشل ولم يفشل`);
}

function check(label, actual, expected) {
  const ok = String(actual) === String(expected);
  if (!ok) failures += 1;
  console.log(`  ${ok ? '✓' : '✗'} ${label}${ok ? '' : ` — توقّعنا ${expected} وجاء ${actual}`}`);
}

console.log('تهيئة مصدر يحاكي النظام السابق…');
runFile('tests/migration/legacy-fixture.sql');
runFile('scripts/migration/01-source-adapter.sql');
runFile('scripts/migration/decisions.sql');
runFile('supabase/migrations/0025_launch_readiness.sql');

console.log('\n١. الفحص المسبق يرفض التشغيل قبل اكتمال القرارات');
{
  const output = expectFailure('scripts/migration/02-preflight.sql', 'الفحص المسبق');
  check('يرفع preflight_failed', /preflight_failed/.test(output), 'true');
  check('يسمّي قرار الدور الناقص', /D0/.test(output), 'true');
}

console.log('\n٢. بعد القرارات وإنشاء الحسابات يمرّ');
runFile('tests/migration/decisions-fixture.sql');
{
  // الحسابات تُنشأ في المشروع الجديد أولًا؛ بدونها يبقى الفحص مانعًا
  const output = expectFailure('scripts/migration/02-preflight.sql', 'الفحص المسبق بلا حسابات');
  check('يمنع الترحيل بلا حسابات في المشروع الجديد', /بلا حساب/.test(output), 'true');
}
runFile('tests/migration/accounts-fixture.sql');
{
  const output = runFileAll('scripts/migration/02-preflight.sql');
  check('لا موانع', /لا موانع/.test(output), 'true');
  check('يبقى تحذير بيانات حساب الإيداع (D8)', /حساب الإيداع/.test(output), 'true');
}

/*
 * إعدادات الإشعارات هي الصفوف الوحيدة التي يعدّلها الترحيل ولا يُنشئها، فهي
 * الوحيدة التي لا يكفي الحذفُ لإعادتها. تُلتقط قبل الترحيل وتُقارن بعد التراجع.
 */
const settingOriginal = psql(
  `select notification_message from order_status_settings where status = 'confirmed'`,
);

console.log('\n٣. التحميل');
runFile('scripts/migration/03-transform-load.sql');

console.log('\n٤. دلالة الحالات — جوهر الترحيل');
const status = (id) => psql(`select status from orders where id = '${id}'`);
check('delivered نسخة 1 ← مكتمل', status('77777777-0000-0000-0000-000000000001'), 'completed');
check(
  'delivered نسخة 2 مع صورة ← مكتمل',
  status('77777777-0000-0000-0000-000000000002'),
  'completed',
);
check(
  'delivered نسخة 2 بلا صورة ← خرج للتوصيل',
  status('77777777-0000-0000-0000-000000000003'),
  'out_for_delivery',
);
check(
  'completed نسخة 1 ← خرج للتوصيل',
  status('77777777-0000-0000-0000-000000000004'),
  'out_for_delivery',
);
check('processing ينتقل كما هو', status('77777777-0000-0000-0000-000000000005'), 'processing');
check('cancelled ينتقل كما هو', status('77777777-0000-0000-0000-000000000006'), 'cancelled');

console.log('\n٥. القرارات البشرية طُبِّقت');
check(
  'D4: الطلب غير المدفوع صار مدفوعًا نقدًا',
  psql(`select payment_status || '/' || payment_method from orders
         where id = '77777777-0000-0000-0000-000000000007'`),
  'paid/cash_on_delivery',
);
check(
  'D1: العميل اليتيم ربُط بعقار',
  psql(`select count(*) from customers where property_id is null`),
  '0',
);
check(
  'الهاتف المكرر نُزع من غير مالكه',
  psql(`select coalesce(phone, 'فارغ') from customers
         where id = '33333333-0000-0000-0000-000000000006'`),
  'فارغ',
);
check(
  'وملفه صار ناقصًا ليُستكمل عند أول مسح',
  psql(`select profile_status from customers where id = '33333333-0000-0000-0000-000000000006'`),
  'incomplete',
);
check(
  'الملغي بلا سبب أخذ السبب المقرَّر',
  psql(`select length(btrim(cancel_reason)) >= 3 from orders
         where id = '77777777-0000-0000-0000-000000000006'`),
  't',
);
check(
  'الموظف غير الفعّال لم يُرحَّل',
  psql(`select count(*) from staff where id = '11111111-0000-0000-0000-000000000004'`),
  '0',
);
check(
  'الأدوار من قرار D0 لا من المصدر',
  psql(`select role from staff where id = '11111111-0000-0000-0000-000000000002'`),
  'courier',
);

console.log('\n٦. رموز QR — الرموز المطبوعة يجب أن تبقى عاملة');
check(
  'كل رمز قديم له سطر سارٍ بالقيمة نفسها',
  psql(`select count(*) from src.customers sc
         where not exists (select 1 from customer_qr_tokens t
                            where t.token = sc.qr_token and t.revoked_at is null)`),
  '0',
);

console.log('\n٧. النقد التاريخي');
check(
  'تسوية افتتاحية واحدة معتمدة',
  psql(`select count(*) from cash_settlements where state = 'verified'`),
  '1',
);
check(
  'بفرق صفر — لا ذمة وهمية على مندوب يوم الإطلاق',
  psql(`select coalesce(sum(abs(variance)), 0) from cash_settlements`),
  '0.000',
);
check(
  'ومجموعها يساوي النقد المُحصَّل',
  psql(`select confirmed_amount from cash_settlements limit 1`),
  '17.500',
);

console.log('\n٨. سجل الترحيل يفسّر كل تغيير معنى');
check(
  'خمسة طلبات تغيّرت حالتها ومسجّلة',
  psql(`select count(*) from private.migration_log where action = 'status_mapped'`),
  '5',
);
check(
  'ونزع الهاتف مسجّل بسببه',
  psql(`select count(*) from private.migration_log where action = 'phone_dropped'`),
  '1',
);
check(
  'ولكل طلب سطر «مُرحَّل» صريح في سجل الحالات',
  psql(`select count(*) from order_status_history
         where context ->> 'migrated' = 'true'`),
  '7',
);

console.log('\n٩. التحقق');
{
  const output = runFileAll('scripts/migration/05-verify.sql');
  check('اجتاز كل الفحوص', /قابل للاعتماد/.test(output), 'true');
  check('لا فحص فاشل', psql(`select count(*) from src.verify() where not passed`), '0');
}

console.log('\n١٠. الترحيل لا يُعاد فوق نفسه');
{
  const output = expectFailure('scripts/migration/03-transform-load.sql', 'إعادة التحميل');
  check('يرفض تحميلًا ثانيًا', /migration_already_run/.test(output), 'true');
}

console.log('\n١١. التراجع يحرسه نشاط ما بعد الترحيل');
psql(`insert into orders (customer_id, property_id, status)
      select id, property_id, 'new' from customers limit 1`);
{
  const output = expectFailure('scripts/migration/06-rollback.sql', 'التراجع غير الآمن');
  check('يرفض المحو حين وُجد طلب جديد', /rollback_unsafe/.test(output), 'true');
}
psql(`begin;
      drop rule osh_no_delete on order_status_history;
      delete from order_status_history h
       where not exists (select 1 from src.orders s where s.id = h.order_id);
      delete from orders o where not exists (select 1 from src.orders s where s.id = o.id);
      create rule osh_no_delete as on delete to order_status_history do instead nothing;
      commit;`);

console.log('\n١٢. التراجع الكامل');
check(
  'نصّ الإشعار استُبدل بنصّ النظام السابق',
  psql(`select notification_message from order_status_settings where status = 'confirmed'`) ===
    settingOriginal,
  'false',
);
runFile('scripts/migration/06-rollback.sql');
check('لا طلبات', psql('select count(*) from orders'), '0');
check('لا عملاء', psql('select count(*) from customers'), '0');
check('لا موظفين', psql('select count(*) from staff'), '0');
check('لا رموز', psql('select count(*) from customer_qr_tokens'), '0');
check('لا تسويات', psql('select count(*) from cash_settlements'), '0');
check('لا سجل حالات', psql('select count(*) from order_status_history'), '0');
// الحمايات تعود كما كانت: لا تبقى القاعدة مكشوفة بعد التراجع
check(
  'قاعدة منع حذف سجل الحالات أُعيدت',
  psql(`select count(*) from pg_rules
         where tablename = 'order_status_history' and rulename = 'osh_no_delete'`),
  '1',
);
check(
  'ومحفّزا التسوية مُفعَّلان',
  psql(`select count(*) from pg_trigger
         where tgname in ('trg_settlement_final_lock','trg_cash_collections_recalc')
           and tgenabled = 'O'`),
  '2',
);
check(
  'ونصوص إشعارات الحالات عادت إلى ما كانت عليه',
  psql(`select notification_message from order_status_settings where status = 'confirmed'`),
  settingOriginal,
);
check(
  'وسجل الترحيل احتفظ بأثر المحاولة',
  psql(`select count(*) from private.migration_log where entity = 'run'`),
  '2',
);

console.log('\n١٣. البروفة قابلة للتكرار');
runFile('scripts/migration/03-transform-load.sql');
check('التحميل الثاني نجح', psql('select count(*) from orders'), '7');
check('والتحقق مرّ', psql(`select count(*) from src.verify() where not passed`), '0');

console.log('\nتنظيف…');
runFile('scripts/migration/06-rollback.sql');
psql('drop schema if exists src cascade; drop schema if exists legacy cascade;');
psql(`delete from private.migration_log;
      delete from auth.users where email like '%@myduby.test'`);

if (failures > 0) {
  console.error(`\n✗ فشل ${failures} فحصًا في بروفة الترحيل`);
  process.exit(1);
}

console.log('\n✓ اجتازت بروفة الترحيل كل الفحوص');
