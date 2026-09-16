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
    baseURL: 'http://127.0.0.1:4173',
    trace: 'on-first-retry',
    locale: 'ar',
  },

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        ...(chromiumPath ? { launchOptions: { executablePath: chromiumPath } } : {}),
      },
    },
    { name: 'mobile-safari', use: { ...devices['iPhone SE'] } },
  ],

  webServer: {
    command: 'pnpm --filter @duby/staff preview --port 4173',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
