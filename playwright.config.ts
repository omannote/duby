import { defineConfig, devices } from '@playwright/test';

/*
 * بعض بيئات التشغيل تثبّت Chromium مسبقًا بإصدار مختلف عن الذي تتوقعه حزمة
 * Playwright. عندها يُمرَّر مساره في PLAYWRIGHT_CHROMIUM_PATH بدل تنزيل نسخة
 * ثانية. في CI يبقى الحقل فارغًا فتُستخدم النسخة التي ثبّتها الخط.
 */
const chromiumPath = process.env.PLAYWRIGHT_CHROMIUM_PATH;

/*
 * قيم بناء صريحة للاختبار. بلا قيم يعرض التطبيق شاشة «غير مهيّأ» فتفشل كل
 * الاختبارات لسبب غير حقيقي. وهمية ولا تتصل بمشروع فعلي.
 */
const TEST_ENV = {
  VITE_SUPABASE_URL: 'http://127.0.0.1:54321',
  VITE_SUPABASE_ANON_KEY: 'test-anon-key-not-a-real-credential',
  VITE_APP_VERSION: 'e2e',
};

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
   * يُبنى التطبيق هنا بقيم اختبار صريحة بدل الاعتماد على بيئة الغلاف.
   * بلا قيم يعرض التطبيق شاشة «غير مهيّأ» فتفشل كل الاختبارات لسبب غير حقيقي.
   * القيم وهمية ولا تتصل بمشروع فعلي — الاختبارات هنا لا تلمس قاعدة بيانات.
   */
  webServer: [
    {
      command: 'pnpm --filter @duby/staff build && pnpm --filter @duby/staff preview --port 4173',
      url: 'http://127.0.0.1:4173',
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      env: TEST_ENV,
    },
    {
      command:
        'pnpm --filter @duby/customer build && pnpm --filter @duby/customer preview --port 4174',
      url: 'http://127.0.0.1:4174',
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      env: TEST_ENV,
    },
  ],
});
