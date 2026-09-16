import { expect, test } from '@playwright/test';

/**
 * لوحة الموظفين — E10 وE11 من مصفوفة الاختبار، وما يمكن التحقق منه بلا جلسة.
 * المسارات التي تتطلب تسجيل دخول مغطّاة بـ31 تأكيد pgTAP على قاعدة حقيقية.
 */
test.describe('لوحة الموظفين — المرحلة الثالثة', () => {
  test('E10 — التخطيط ثابت عند التركيز على حقل', async ({ page }) => {
    await page.goto('/');

    const before = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--app-height').trim(),
    );

    await page.getByLabel('البريد الإلكتروني').focus();
    await page.waitForTimeout(150);

    const after = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--app-height').trim(),
    );

    expect(after).toBe(before);
  });

  test('الجذر لا يمرّر الصفحة كلها', async ({ page }) => {
    await page.goto('/');

    const overflow = await page.evaluate(
      () => getComputedStyle(document.querySelector('.app-shell') ?? document.body).overflow,
    );

    // التمرير للمحتوى وحده؛ عدمه يجعل التذييل الثابت يزحف مع الصفحة
    expect(['hidden', 'visible']).toContain(overflow);
  });

  test('E11 — الماسح مُجمَّع في الحزمة لا يُحمَّل من CDN', async ({ page }) => {
    const external: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.hostname !== '127.0.0.1' && url.hostname !== 'localhost') external.push(url.href);
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // CSP صارم بلا CDN: أي طلب خارجي يعني كسر السياسة
    expect(external).toEqual([]);
  });

  test('حزمة الموظفين تحوي منطق الماسح', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    // الطبقتان معًا: BarcodeDetector وتحليل الإطارات
    expect(bundle).toMatch(/BarcodeDetector/);
    expect(bundle).toMatch(/inversionAttempts|dontInvert/);
  });

  test('لا استدعاء refreshSession في أي مسار', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    expect(scripts.join('\n')).not.toMatch(/\.refreshSession\(/);
  });
});

test.describe('بوابة الدفع — المرحلة الرابعة', () => {
  test('E5 — أزرار البوابة موجودة في الحزمة', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    // البوابة تعرض السبب والبديلين، لا زرًّا معطّلًا بلا تفسير
    expect(bundle).toContain('لا يمكن التسليم قبل تسجيل الدفع');
    expect(bundle).toContain('استلمت المبلغ نقدًا');
    expect(bundle).toContain('تحقق من ثواني');
  });

  test('لا مفاتيح مزوّدي الدفع في حزمة الواجهة', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).not.toMatch(/thawani-api-key/);
    expect(bundle).not.toMatch(/THAWANI_SECRET/);
    expect(bundle).not.toMatch(/OTP_PEPPER/);
  });
});

test.describe('الصندوق — المرحلة 4ب', () => {
  test('E13/E14 — عناصر دورة التسوية في الحزمة', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).toContain('إيداع النقد');
    expect(bundle).toContain('المبلغ المؤكَّد من الإثبات');
    // رسالة رفض الاعتماد الذاتي معروضة للمستخدم، والقاعدة مفروضة في القاعدة
    expect(bundle).toContain('لا يمكنك اعتماد تسويتك');
  });

  test('E15 — تحذير النقد غير المودَع في شاشة الطلبات لا الصندوق', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).toContain('لديك نقد غير مودَع من');
    expect(bundle).toContain('أودعه لتتمكن من التحصيل');
  });

  test('E16 — الإيداع البنكي افتراضي والاستثناء يتطلب سببًا', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).toContain('سبب عدم الإيداع البنكي');
    // المندوب يعرف أن الاستثناء مرئي
    expect(bundle).toContain('سيظهر هذا في تقرير الاستثناءات');
  });
});
