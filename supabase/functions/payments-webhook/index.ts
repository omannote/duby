/**
 * استقبال إشعار الدفع من ثواني — الطبقة الأولى والأساسية لتأكيد الدفع.
 *
 * بلا JWT لأن المستدعي خادم لا مستخدم، والحماية بالتوقيع.
 */
import { serviceClient } from '../_shared/auth.ts';
import { paymentProvider } from '../_shared/thawani.ts';

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response('method not allowed', { status: 405 });
  }

  // الجسم يُقرأ نصًّا أولًا: التحقق من التوقيع قبل أي تحليل
  const rawBody = await request.text();
  const signature = request.headers.get('thawani-signature') ??
    request.headers.get('x-signature');

  const valid = await paymentProvider().verifyWebhook(rawBody, signature);

  if (!valid) {
    console.error(JSON.stringify({
      level: 'error',
      fn: 'payments-webhook',
      outcome: 'invalid_signature',
      has_signature: Boolean(signature),
    }));
    return new Response('invalid signature', { status: 401 });
  }

  let payload: { data?: { session_id?: string; payment_status?: string } };
  try {
    payload = JSON.parse(rawBody) as typeof payload;
  } catch {
    return new Response('bad request', { status: 400 });
  }

  const sessionId = payload.data?.session_id;
  const status = payload.data?.payment_status ?? 'unknown';

  if (!sessionId) return new Response('missing session', { status: 400 });

  await serviceClient().rpc('fn_apply_payment_webhook', {
    p_session_id: sessionId,
    p_provider_status: status,
    // الحمولة تُحفظ منقّحة: الحقول غير الحساسة فقط
    p_safe_payload: { session_id: sessionId, payment_status: status },
  });

  /*
   * 200 دائمًا بعد المعالجة، حتى لو لم تُطبَّق: الدالة معادة الأمان، وإعادة
   * الإرسال اللانهائية من المزود لا تفيد أحدًا.
   */
  return new Response('ok', { status: 200 });
});
