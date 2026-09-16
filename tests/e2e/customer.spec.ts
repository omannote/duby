import { expect, test } from '@playwright/test';

/**
 * رحلة العميل — E1 و E2 من مصفوفة الاختبار.
 *
 * تعمل مقابل خادم وهمي: الهدف هو سلوك الواجهة وحدودها، أما منطق الأعمال
 * فمُثبت بـ43 تأكيد pgTAP على قاعدة حقيقية.
 */
const TOKEN = '33333333-3333-3333-3333-333333333333';
const SESSION = '44444444-4444-4444-4444-444444444444';

type RouteBody = Record<string, unknown>;

async function stubApi(
  page: import('@playwright/test').Page,
  handlers: Record<string, (body: RouteBody) => unknown>,
) {
  await page.route('**/functions/v1/public-qr**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname.replace(/^.*\/public-qr/, '') || '/scan';
    const body = JSON.parse(route.request().postData() ?? '{}') as RouteBody;
    const handler = handlers[path];

    if (!handler) {
      await route.fulfill({ status: 404, body: '{}' });
      return;
    }

    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(handler(body)),
    });
  });
}

test.describe('رحلة العميل', () => {
  test('بلا رمز في الرابط تظهر رسالة صريحة', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('alert')).toContainText('لا يوجد رمز في الرابط');
  });

  test('E1 — عميل جديد: بيانات ثم تحقق ثم صورة ثم طلب', async ({ page }) => {
    await stubApi(page, {
      '/scan': () => ({
        ok: true,
        request_id: 'req1',
        data: {
          scan_session_id: SESSION,
          profile_status: 'incomplete',
          phone_masked: null,
          can_request_otp: false,
          resend_available_in: 0,
        },
      }),
      '/complete-profile': () => ({ ok: true, request_id: 'req2', data: { next: 'request_otp' } }),
      '/request-otp': () => ({
        ok: true,
        request_id: 'req3',
        data: { expires_in: 300, resend_available_in: 60, attempts_remaining: 5 },
      }),
      '/verify-otp': () => ({
        ok: true,
        request_id: 'req4',
        data: { submission_token: 'tok', next: 'capture_photo' },
      }),
    });

    await page.goto(`/?t=${TOKEN}`);

    await expect(page.getByRole('heading', { name: 'أهلًا بك' })).toBeVisible();

    // لا حقل للعقار ولا قائمة عقارات — العميل لا يراها ولا يختارها
    await expect(page.getByText('العقار')).toHaveCount(0);
    await expect(page.locator('select')).toHaveCount(0);

    await page.getByLabel('الاسم الكامل').fill('أحمد سالم');
    await page.getByLabel('رقم الهاتف').fill('91234567');
    await page.getByLabel('الطابق').fill('3');
    await page.getByLabel('رقم الشقة').fill('12');
    await page.getByRole('button', { name: 'متابعة' }).click();

    await expect(page.getByRole('heading', { name: 'تأكيد رقمك' })).toBeVisible();
    await page.getByRole('button', { name: 'إرسال رمز التحقق' }).click();

    await expect(page.getByRole('heading', { name: 'أدخل الرمز' })).toBeVisible();
    await page.getByLabel('رمز التحقق').fill('123456');
    await page.getByRole('button', { name: 'تحقق' }).click();

    // الطلب لا يُنشأ بعد التحقق: الخطوة التالية هي التصوير
    await expect(page.getByRole('heading', { name: 'صوّر طلبك' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'إرسال الطلب' })).toBeDisabled();
  });

  test('E2 — عميل مكتمل ينتقل مباشرة إلى التحقق', async ({ page }) => {
    await stubApi(page, {
      '/scan': () => ({
        ok: true,
        request_id: 'req1',
        data: {
          scan_session_id: SESSION,
          profile_status: 'complete',
          phone_masked: '+968 ****67',
          can_request_otp: true,
          resend_available_in: 0,
        },
      }),
    });

    await page.goto(`/?t=${TOKEN}`);

    await expect(page.getByRole('heading', { name: 'تأكيد رقمك' })).toBeVisible();
    await expect(page.getByText('+968 ****67')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'أهلًا بك' })).toHaveCount(0);
  });

  test('الرمز المُبطل يُعرض برسالته الخاصة لا «غير صالح»', async ({ page }) => {
    await stubApi(page, {
      '/scan': () => ({
        ok: false,
        code: 'revoked_qr',
        message: 'هذا الرمز أُبطل — اطلب رمزًا جديدًا',
        request_id: 'abc123def456',
      }),
    });

    await page.goto(`/?t=${TOKEN}`);

    await expect(page.getByRole('alert')).toContainText('أُبطل');
    // معرّف الطلب معروض: بلاغ العميل يتحول إلى بحث واحد في السجل
    await expect(page.getByText('abc123')).toBeVisible();
  });

  test('خطأ التحقق يعرض رسالة ومعرّف مرجع', async ({ page }) => {
    await stubApi(page, {
      '/scan': () => ({
        ok: true,
        request_id: 'r',
        data: {
          scan_session_id: SESSION,
          profile_status: 'complete',
          phone_masked: '+968 ****67',
          can_request_otp: true,
          resend_available_in: 0,
        },
      }),
      '/request-otp': () => ({
        ok: true,
        request_id: 'r',
        data: { expires_in: 300, resend_available_in: 60, attempts_remaining: 5 },
      }),
      '/verify-otp': () => ({
        ok: false,
        code: 'otp_invalid',
        message: 'رمز التحقق غير صحيح',
        request_id: 'zzz999zzz999',
      }),
    });

    await page.goto(`/?t=${TOKEN}`);
    await page.getByRole('button', { name: 'إرسال رمز التحقق' }).click();
    await page.getByLabel('رمز التحقق').fill('000000');
    await page.getByRole('button', { name: 'تحقق' }).click();

    await expect(page.getByRole('alert')).toContainText('رمز التحقق غير صحيح');
    await expect(page.getByRole('alert')).toContainText('zzz999');
  });

  test('صفحة العميل لا تحمّل كود لوحة الإدارة', async ({ page }) => {
    const scripts: string[] = [];
    page.on('response', async (response) => {
      if (response.url().endsWith('.js')) scripts.push(await response.text());
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const bundle = scripts.join('\n');
    expect(bundle).not.toMatch(/fn_create_customer_with_qr/);
    expect(bundle).not.toMatch(/fn_upsert_property/);
    expect(bundle).not.toMatch(/service_role/);
  });
});

test.describe('صفحات العودة من الدفع', () => {
  test('E7 — صفحة النجاح لا تؤكد الدفع', async ({ page }) => {
    await page.goto('/payment/success?rt=abc&success=true');

    await expect(page.getByRole('heading', { name: 'شكرًا لك' })).toBeVisible();

    // معامل success في الرابط ليس دليل دفع: الصفحة تقول «نتحقق» لا «تم الدفع»
    await expect(page.getByText('نتحقق من عملية الدفع')).toBeVisible();
    await expect(page.getByText('تم الدفع بنجاح')).toHaveCount(0);
  });

  test('صفحة الإلغاء تعرض بديلًا واضحًا', async ({ page }) => {
    await page.goto('/payment/cancel?rt=abc');

    await expect(page.getByRole('heading', { name: 'لم تكتمل عملية الدفع' })).toBeVisible();
    await expect(page.getByText('واتساب')).toBeVisible();
  });

  test('صفحات الدفع لا تستدعي أي واجهة', async ({ page }) => {
    const calls: string[] = [];
    page.on('request', (request) => {
      if (request.url().includes('/functions/v1/')) calls.push(request.url());
    });

    await page.goto('/payment/success?rt=abc');
    await page.waitForLoadState('networkidle');

    // لا استعلام من صفحة عامة: التأكيد كله على الخادم
    expect(calls).toEqual([]);
  });
});
