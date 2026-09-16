#!/usr/bin/env node
/**
 * يتحقق أن قائمة وظائف Edge واحدة في ثلاثة أماكن.
 *
 * التباعد هنا لا يظهر إلا في CI: `supabase start` يفشل عند وظيفة مُعلنة في
 * config.toml بلا مجلد، ووظيفة بلا إعلان تُنشر بإعداد افتراضي غير مقصود،
 * ووظيفة خارج قائمة `check:functions` لا يفحصها deno أبدًا. الثلاثة وقعت.
 *
 * الاستخدام: pnpm verify:functions
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const FUNCTIONS_DIR = 'supabase/functions';

const onDisk = readdirSync(FUNCTIONS_DIR, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && !entry.name.startsWith('_'))
  .filter((entry) => existsSync(`${FUNCTIONS_DIR}/${entry.name}/index.ts`))
  .map((entry) => entry.name)
  .sort();

const config = readFileSync('supabase/config.toml', 'utf8');
const declared = [...config.matchAll(/^\[functions\.([a-z0-9-]+)\]/gm)]
  .map((match) => match[1])
  .sort();

const checkScript = JSON.parse(readFileSync('package.json', 'utf8')).scripts['check:functions'];
const checked = [...checkScript.matchAll(/([a-z0-9-]+)\/index\.ts/g)]
  .map((match) => match[1])
  .sort();

const problems = [];

for (const name of onDisk) {
  if (!declared.includes(name)) problems.push(`«${name}» على القرص وغير معلنة في config.toml`);
  if (!checked.includes(name)) problems.push(`«${name}» على القرص وخارج قائمة check:functions`);
}

for (const name of declared) {
  if (!onDisk.includes(name)) {
    problems.push(`«${name}» معلنة في config.toml ولا مجلد لها — supabase start سيفشل`);
  }
}

for (const name of checked) {
  if (!onDisk.includes(name)) problems.push(`«${name}» في check:functions ولا مجلد لها`);
}

if (problems.length > 0) {
  console.error('✗ قائمة وظائف Edge متباعدة:\n');
  for (const problem of problems) console.error(`  • ${problem}`);
  process.exit(1);
}

console.log(`✓ وظائف Edge متطابقة في المواضع الثلاثة (${onDisk.length}): ${onDisk.join('، ')}`);
