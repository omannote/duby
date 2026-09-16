import { expect, test } from '@playwright/test';

/**
 * دخان لوحة الموظفين: يثبت أن الحزمة المبنية تعمل في متصفح حقيقي.
 * الرحلات الكاملة (E1–E19) تأتي مع مراحلها.
 */
test.describe('لوحة الموظفين', () => {
  test('تعرض شاشة الدخول لغير المسجّل', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'دوبي' })).toBeVisible();
    await expect(page.getByLabel('البريد الإلكتروني')).toBeVisible();
    await expect(page.getByLabel('كلمة المرور')).toBeVisible();
    await expect(page.getByRole('button', { name: 'تسجيل الدخول' })).toBeVisible();
  });

  test('لا تكشف أي بيانات قبل الدخول', async ({ page }) => {
    await page.goto('/');

    // لا تبويبات ولا قوائم: الواجهة لا تحمّل شيئًا قبل التحقق من الجلسة
    await expect(page.getByRole('button', { name: 'العملاء' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'العقارات' })).toHaveCount(0);
  });

  test('حقول النموذج لا تسبب تقريب Safari', async ({ page }) => {
    await page.goto('/');

    // أقل من 16px يجعل Safari يقرّب الصفحة تلقائيًا عند التركيز
    const fontSize = await page
      .getByLabel('البريد الإلكتروني')
      .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));

    expect(fontSize).toBeGreaterThanOrEqual(16);
  });

  test('الصفحة عربية باتجاه RTL', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
  });

  test('لا تمرير أفقي على أصغر شاشة مستهدفة', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 568 });
    await page.goto('/');

    const overflows = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflows).toBe(false);
  });

  test('ارتفاع التطبيق مثبّت على visualViewport', async ({ page }) => {
    await page.goto('/');

    const appHeight = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--app-height').trim(),
    );
    expect(appHeight).toMatch(/^\d+(\.\d+)?px$/);
  });

  test('لا مفاتيح حساسة في الحزمة المُحمَّلة', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).not.toMatch(/service_role/);
    expect(bundle).not.toMatch(/wab_live_/);
    expect(bundle).not.toMatch(/sk_(live|test)_/);
  });

  test('لا استدعاء refreshSession في حزمة الواجهة', async ({ page }) => {
    // السبب الجذري لعطل تأكيد التسليم في النظام السابق — اختبار منع تراجع
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    expect(scripts.join('\n')).not.toMatch(/\.refreshSession\(/);
  });
});
