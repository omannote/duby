#!/usr/bin/env node
/**
 * يتحقق أن Service Worker المبني لا يعترض Supabase ولا يخزّنه.
 *
 * في النظام السابق اعترض SW طلبات Supabase، فخزّن بيانات عملاء في كاش
 * المتصفح وقدّم نسخة قديمة أثناء التشخيص. الاسم يُصغَّر عند البناء، فلا يكفي
 * أن تكون القاعدة في المصدر — لا بد من التحقق من الناتج.
 */
import { existsSync, readFileSync } from 'node:fs';

const SW_PATH = 'apps/staff/dist/sw.js';

if (!existsSync(SW_PATH)) {
  console.error(`لم يُبنَ Service Worker بعد: ${SW_PATH}. شغّل pnpm build أولًا.`);
  process.exit(1);
}

const source = readFileSync(SW_PATH, 'utf8');
const failures = [];

// قاعدة الاستثناء موجودة في الناتج المُصغَّر
if (!source.includes('supabase.co')) {
  failures.push('قاعدة استثناء Supabase مفقودة من Service Worker المبني');
}

// لا مسار Supabase داخل قائمة الأصول المُخزَّنة مسبقًا
const precacheEntries = [...source.matchAll(/"url":"([^"]+)"/g)].map((match) => match[1]);
const leaked = precacheEntries.filter((url) => url.includes('supabase'));

if (leaked.length > 0) {
  failures.push(`مسارات Supabase داخل precache: ${leaked.join(', ')}`);
}

if (precacheEntries.length === 0) {
  failures.push('قائمة الأصول المُخزَّنة مسبقًا فارغة — هل فشل حقن الملفات؟');
}

if (failures.length > 0) {
  console.error('\n✗ فحص Service Worker:\n');
  for (const failure of failures) console.error(`  • ${failure}`);
  process.exit(1);
}

console.log(`✓ Service Worker سليم — ${precacheEntries.length} أصول مخزّنة، ولا اعتراض لـSupabase`);
