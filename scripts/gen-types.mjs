#!/usr/bin/env node
/**
 * يولّد أنواع TypeScript من مخطط قاعدة البيانات (ADR-002).
 *
 * في CI يتبعه `git diff --exit-code`: هجرة تغيّر المخطط دون تحديث الأنواع
 * تُفشل البناء — فيستحيل أن تتباعد الواجهة عن قاعدة البيانات بصمت.
 */
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

/*
 * pgTAP يُثبَّت في قواعد الاختبار وحدها، ويضيف نحو ١٥٠ دالة ونوعًا مركّبًا إلى
 * مخطط public. توليد الأنواع من قاعدة يحمله يُنتج ملفًا لا يطابق ما يولّده CI
 * من قاعدة نظيفة، فتحمرّ بوابة التباعد بلا تباعد حقيقي. حدث ذلك فعلًا.
 */
function assertCleanSchema(dbUrl) {
  const found = execFileSync(
    'psql',
    [dbUrl, '-X', '-q', '-t', '-A', '-c', "select 1 from pg_extension where extname = 'pgtap'"],
    { encoding: 'utf8' },
  ).trim();

  if (found) {
    console.error('pgTAP مُثبَّت في هذه القاعدة. ولّد الأنواع من قاعدة نظيفة:');
    console.error('  supabase db reset && pnpm gen:types');
    process.exit(1);
  }
}

const OUTPUT = 'packages/shared/src/db.ts';
const projectRef = process.env.SUPABASE_PROJECT_REF;

const args = projectRef
  ? ['gen', 'types', 'typescript', '--project-id', projectRef]
  : ['gen', 'types', 'typescript', '--local'];

const banner = `/* مولَّد آليًا من مخطط قاعدة البيانات — لا تحرّره يدويًا.
 * أعد التوليد بـ: pnpm gen:types
 */\n\n`;

const localDbUrl =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

if (!projectRef) {
  assertCleanSchema(localDbUrl);
}

try {
  const types = execFileSync('supabase', args, { encoding: 'utf8' });
  writeFileSync(OUTPUT, banner + types);
  console.log(`✓ كُتبت الأنواع إلى ${OUTPUT}`);
} catch (error) {
  console.error('تعذّر توليد الأنواع. هل قاعدة Supabase المحلية تعمل؟ شغّل: pnpm db:start');
  console.error(error.message);
  process.exit(1);
}
