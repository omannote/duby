import { expect, test } from '@playwright/test';

/**
 * دخان المرحلة صفر: يثبت أن الحزمة المبنية تعمل فعلًا في متصفح حقيقي.
 * الرحلات الكاملة (E1–E19) تأتي مع مراحلها.
 */
test.describe('لوحة الموظفين — المرحلة صفر', () => {
  test('تُحمّل وتعرض إصدارها', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'مرحبًا يا دوبي' })).toBeVisible();
    await expect(page.getByText('الإصدار')).toBeVisible();
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
});
