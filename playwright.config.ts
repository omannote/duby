import { defineConfig, devices } from '@playwright/test';

/*
 * بعض بيئات التشغيل تثبّت Chromium مسبقًا بإصدار مختلف عن الذي تتوقعه حزمة
 * Playwright. عندها يُمرَّر مساره في PLAYWRIGHT_CHROMIUM_PATH بدل تنزيل نسخة
 * ثانية. في CI يبقى الحقل فارغًا فتُستخدم النسخة التي ثبّتها الخط.
 */
const chromiumPath = process.env.PLAYWRIGHT_CHROMIUM_PATH;

/**
 * WebKit مُدرج عمدًا: Safari على iPhone هو المتصفح الذي تعثّر فيه النظام
 * السابق مرتين (BarcodeDetector غير مدعوم، والتخطيط يتضخّم مع لوحة المفاتيح).
 * اختباره على Chromium وحده كان سيخفي العطلين.
 */
export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',

  use: {
    trace: 'on-first-retry',
    locale: 'ar',
  },

  projects: [
    {
      name: 'chromium',
      testIgnore: /customer\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        baseURL: 'http://127.0.0.1:4173',
        ...(chromiumPath ? { launchOptions: { executablePath: chromiumPath } } : {}),
      },
    },
    {
      // صفحة العميل تُختبر بمقاس هاتف: هي الجهاز الوحيد الذي تُستخدم عليه
      name: 'customer',
      testMatch: /customer\.spec\.ts/,
      use: {
        ...devices['iPhone SE'],
        baseURL: 'http://127.0.0.1:4174',
        defaultBrowserType: 'chromium',
        ...(chromiumPath ? { launchOptions: { executablePath: chromiumPath } } : {}),
      },
    },
    {
      name: 'mobile-safari',
      testIgnore: /customer\.spec\.ts/,
      use: { ...devices['iPhone SE'], baseURL: 'http://127.0.0.1:4173' },
    },
  ],

  /*
   * تخدم ما بناه scripts/e2e-build.mjs، ولا تبني. القيم مخبوزة في الحزمة
   * وقت البناء فلا يحتاجها preview، والمهلة تخصّ الصعود وحده لا بناءً كاملًا.
   *
   * `--host 127.0.0.1` صريح: vite preview يربط على `localhost` افتراضيًا،
   * وهو على بعض العدّادات يُحلّ إلى ::1 وحدها بينما يستطلع Playwright العنوان
   * الرابع — فلا يردّ أحد وتنقضي المهلة بلا خطأ يفسّرها.
   *
   * `--strictPort` كذلك: بدونه ينتقل vite إلى المنفذ التالي حين يكون المنفذ
   * مشغولًا، فيبقى العنوان المُستطلَع صامتًا وتظهر المشكلة مهلةً منقضية لا
   * منفذًا مشغولًا.
   */
  webServer: [
    {
      command: 'pnpm --filter @duby/staff preview --host 127.0.0.1 --port 4173 --strictPort',
      url: 'http://127.0.0.1:4173',
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
    {
      command: 'pnpm --filter @duby/customer preview --host 127.0.0.1 --port 4174 --strictPort',
      url: 'http://127.0.0.1:4174',
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],
});
