#!/usr/bin/env node
/**
 * يبني التطبيقين بقيم اختبار صريحة قبل اختبارات المتصفح.
 *
 * البناء منفصل عن `webServer` عمدًا. حين كان كل خادم يبني تطبيقه، كان بناءان
 * يتنافسان على معالجَي العدّاء داخل مهلة الخادم نفسها، فتنقضي المهلة قبل أن
 * يصعد أيٌّ منهما وتُقرأ النتيجة «تعذّر تشغيل الخادم» لا «البناء أبطأ من
 * المهلة». (وglobalSetup لا يصلح: Playwright يشغّل الخوادم قبله.)
 *
 * القيم تُخبز في الحزمة وقت البناء، فـ`preview` لا يحتاجها.
 */
import { execFileSync } from 'node:child_process';

/*
 * بلا هذه القيم يعرض التطبيق شاشة «غير مهيّأ» فتفشل كل الاختبارات لسبب غير
 * حقيقي. وهمية ولا تتصل بمشروع فعلي — اختبارات المتصفح لا تلمس قاعدة بيانات.
 */
const TEST_ENV = {
  VITE_SUPABASE_URL: 'http://127.0.0.1:54321',
  VITE_SUPABASE_ANON_KEY: 'test-anon-key-not-a-real-credential',
  VITE_APP_VERSION: 'e2e',
};

execFileSync('pnpm', ['-r', 'build'], {
  stdio: 'inherit',
  env: { ...process.env, ...TEST_ENV },
});
