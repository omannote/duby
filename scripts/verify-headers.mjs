#!/usr/bin/env node
/**
 * يتحقق أن ترويسات الأمن المطلوبة موجودة ومطابقة للمواصفة.
 *
 * هذا ليس فحصًا تجميليًا: استضافة النظام السابق أرسلت
 * `Permissions-Policy: camera=()` فعطّلت الماسح، و`CSP` يمنع الاتصال بـ
 * Supabase — وكلاهما شُخِّص أولًا كخطأ في الكود، لا في الترويسات.
 *
 * وضعان:
 *   --file  يفحص ملف _headers في المستودع   (في CI، قبل النشر)
 *   <url>   يفحص الاستجابة الحقيقية          (بعد النشر)
 *
 * الوضع الأول يمنع الخطأ من الوصول إلى الإنتاج أصلًا، لأن Cloudflare وحده
 * يفسّر _headers فلا يكشف الخطأ إلا بعد نشره.
 */
import { readFileSync } from 'node:fs';

/** فحوص لا يجوز أن يمر نشر بدونها. */
const REQUIRED = [
  {
    header: 'strict-transport-security',
    test: (v) => /max-age=\d{7,}/.test(v),
    why: 'HSTS بمدة سنة على الأقل',
  },
  {
    header: 'x-content-type-options',
    test: (v) => v.trim() === 'nosniff',
    why: 'منع تخمين نوع المحتوى',
  },
  {
    header: 'referrer-policy',
    test: (v) => v.includes('strict-origin'),
    why: 'عدم تسريب الرابط الكامل — رموز QR تظهر في الروابط',
  },
  {
    header: 'permissions-policy',
    test: (v) => /camera=\(self\)/.test(v),
    why: 'الكاميرا مسموحة للموقع نفسه — بدونها يتعطّل ماسح QR',
  },
  {
    header: 'content-security-policy',
    test: (v) => /connect-src[^;]*supabase\.co/.test(v),
    why: 'السماح بالاتصال بـ Supabase — بدونه يظهر Failed to fetch',
  },
  {
    header: 'content-security-policy',
    test: (v) => /frame-ancestors\s+'none'/.test(v),
    why: 'منع تضمين الصفحة في إطار',
  },
  {
    header: 'content-security-policy',
    test: (v) => !/script-src[^;]*unsafe-inline/.test(v),
    why: "script-src بلا 'unsafe-inline' — ممكن لأن البناء يخرج ملفات منفصلة",
  },
  {
    header: 'content-security-policy',
    test: (v) => /object-src\s+'none'/.test(v),
    why: 'منع المكوّنات الإضافية',
  },
];

/** يقرأ ترويسات المسار العام `/*` من ملف _headers بصيغة Cloudflare Pages. */
function parseHeadersFile(path) {
  const headers = new Map();
  let inGlobalBlock = false;

  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (line.trim() === '' || line.startsWith('#')) continue;

    if (!/^\s/.test(line)) {
      inGlobalBlock = line.trim() === '/*';
      continue;
    }

    if (!inGlobalBlock) continue;

    const separator = line.indexOf(':');
    if (separator === -1) continue;
    headers.set(line.slice(0, separator).trim().toLowerCase(), line.slice(separator + 1).trim());
  }

  return { get: (name) => headers.get(name) ?? null };
}

function check(headers, label) {
  const failures = [];

  for (const rule of REQUIRED) {
    const value = headers.get(rule.header);
    if (!value) {
      failures.push(`${rule.header}: مفقودة — ${rule.why}`);
    } else if (!rule.test(value)) {
      failures.push(`${rule.header}: لا تطابق المواصفة — ${rule.why}\n    القيمة: ${value}`);
    }
  }

  if (failures.length > 0) {
    console.error(`\n✗ ${label}`);
    for (const failure of failures) console.error(`  • ${failure}`);
    return false;
  }

  console.log(`✓ ${label} — اجتاز ${REQUIRED.length} فحوص`);
  return true;
}

const args = process.argv.slice(2);

if (args.length === 0) {
  console.error('الاستخدام:');
  console.error('  node scripts/verify-headers.mjs --file apps/staff/public/_headers');
  console.error('  node scripts/verify-headers.mjs https://app.myduby.com');
  process.exit(2);
}

let allPassed = true;

if (args[0] === '--file') {
  const paths = args.slice(1);
  if (paths.length === 0) {
    console.error('--file يتطلب مسار ملف واحدًا على الأقل');
    process.exit(2);
  }
  for (const path of paths) {
    if (!check(parseHeadersFile(path), path)) allPassed = false;
  }
} else {
  for (const url of args) {
    const response = await fetch(url, { redirect: 'follow' });
    if (!check(response.headers, `${url} (HTTP ${response.status})`)) allPassed = false;
  }
}

process.exit(allPassed ? 0 : 1);
