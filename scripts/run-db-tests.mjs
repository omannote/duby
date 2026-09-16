#!/usr/bin/env node
/**
 * يشغّل اختبارات pgTAP على قاعدة Supabase المحلية.
 * يتطلب `supabase start` مسبقًا.
 */
import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

const DB_URL =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const TEST_DIR = 'tests/db';

function psql(sql) {
  return execFileSync('psql', [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-c', sql], {
    encoding: 'utf8',
  });
}

try {
  psql('create extension if not exists pgtap;');
} catch (error) {
  console.error('تعذّر تفعيل pgTAP. هل قاعدة Supabase المحلية تعمل؟ شغّل: pnpm db:start');
  console.error(error.message);
  process.exit(1);
}

const files = readdirSync(TEST_DIR)
  .filter((name) => name.endsWith('.test.sql'))
  .sort();

if (files.length === 0) {
  console.error('لا توجد ملفات اختبار في', TEST_DIR);
  process.exit(1);
}

let failed = 0;

for (const file of files) {
  const path = join(TEST_DIR, file);
  process.stdout.write(`\n── ${file}\n`);
  try {
    const output = execFileSync('psql', [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-f', path], {
      encoding: 'utf8',
    });
    process.stdout.write(output);
    if (/^not ok/m.test(output)) failed += 1;
  } catch (error) {
    process.stdout.write(error.stdout ?? '');
    console.error(error.stderr ?? error.message);
    failed += 1;
  }
}

if (failed > 0) {
  console.error(`\n✗ فشل ${failed} من ${files.length} ملفات الاختبار`);
  process.exit(1);
}

console.log(`\n✓ نجحت كل اختبارات قاعدة البيانات (${files.length} ملفات)`);
