#!/usr/bin/env node
/**
 * يولّد أنواع TypeScript من مخطط قاعدة البيانات (ADR-002).
 *
 * في CI يتبعه `git diff --exit-code`: هجرة تغيّر المخطط دون تحديث الأنواع
 * تُفشل البناء — فيستحيل أن تتباعد الواجهة عن قاعدة البيانات بصمت.
 */
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const OUTPUT = 'packages/shared/src/db.ts';
const projectRef = process.env.SUPABASE_PROJECT_REF;

const args = projectRef
  ? ['gen', 'types', 'typescript', '--project-id', projectRef]
  : ['gen', 'types', 'typescript', '--local'];

const banner = `/* مولَّد آليًا من مخطط قاعدة البيانات — لا تحرّره يدويًا.
 * أعد التوليد بـ: pnpm gen:types
 */\n\n`;

try {
  const types = execFileSync('supabase', args, { encoding: 'utf8' });
  writeFileSync(OUTPUT, banner + types);
  console.log(`✓ كُتبت الأنواع إلى ${OUTPUT}`);
} catch (error) {
  console.error('تعذّر توليد الأنواع. هل قاعدة Supabase المحلية تعمل؟ شغّل: pnpm db:start');
  console.error(error.message);
  process.exit(1);
}
