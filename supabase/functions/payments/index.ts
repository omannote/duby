/**
 * وظيفة الفوترة والدفع.
 *
 * تحمل مفتاح ثواني السري، وهو سبب وجودها: لا نداء للمزود من المتصفح.
 */
import { corsHeaders } from '../_shared/cors.ts';
import { err, ok, requestIdFrom } from '../_shared/result.ts';
import { requireStaff, serviceClient } from '../_shared/auth.ts';
import { paymentProvider } from '../_shared/thawani.ts';

type Json = Record<string, unknown>;
type DbResult = { ok: boolean; code?: string; message?: string; data?: Json };

Deno.serve(async (request) => {
  const origin = request.headers.get('Origin');
  const requestId = requestIdFrom(request);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (request.method !== 'POST') return err('invalid_input', requestId, origin, 'POST فقط');

  const staff = await requireStaff(request);
  if (!staff) return err('forbidden', requestId, origin);

  let body: Json;
  try {
    body = (await request.json()) as Json;
  } catch {
    return err('invalid_input', requestId, origin, 'جسم الطلب غير صالح');
  }

  const route = new URL(request.url).pathname.replace(/^\/payments/, '') || '/';

  try {
    switch (route) {
      case '/invoice':
        return await handleInvoice(staff, body, requestId, origin);
      case '/verify':
        return await handleVerify(body, requestId, origin);
      case '/cash':
        return relay(
          await staff.client.rpc('fn_record_cash_payment', { p_order_id: body.order_id }),
          requestId,
          origin,
        );
      case '/reverse':
        return relay(
          await staff.client.rpc('fn_reverse_payment', {
            p_order_id: body.order_id,
            p_reason: body.reason,
          }),
          requestId,
          origin,
        );
      default:
        return err('invalid_input', requestId, origin, 'مسار غير معروف');
    }
  } catch (error) {
    console.error(JSON.stringify({
      level: 'error',
      fn: 'payments',
      route,
      request_id: requestId,
      actor_role: staff.role,
      message: error instanceof Error ? error.message : 'unknown',
    }));
    return err('server_error', requestId, origin);
  }
});

function relay(
  response: { data: unknown; error: { message: string } | null },
  requestId: string,
  origin: string | null,
): Response {
  if (response.error) return err('server_error', requestId, origin);

  const result = response.data as DbResult;
  return result.ok
    ? ok(result.data ?? {}, requestId, origin)
    : err(result.code ?? 'server_error', requestId, origin, result.message);
}

/**
 * الفوترة على مرحلتين: الحجز يقفل رقم الفاتورة قبل أي نداء خارجي، ثم يُربط
 * بجلسة الدفع. فشل المزود يُحرّر الحجز فلا فاتورة ولا انتقال حالة ولا جلسة
 * دفع يتيمة قابلة للسداد.
 */
async function handleInvoice(
  staff: NonNullable<Awaited<ReturnType<typeof requireStaff>>>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const amount = Number(body.amount ?? 0);
  const invoiceNumber = String(body.invoice_number ?? '').trim();

  const reserved = await staff.client.rpc('fn_reserve_invoice', {
    p_order_id: body.order_id,
    p_invoice_number: invoiceNumber,
    p_amount: amount,
    p_idempotency_key: `inv:${invoiceNumber}:${crypto.randomUUID()}`,
  });

  if (reserved.error) return err('server_error', requestId, origin);

  const reservation = reserved.data as DbResult;
  if (!reservation.ok) {
    return err(reservation.code ?? 'server_error', requestId, origin, reservation.message);
  }

  const paymentId = String(reservation.data?.payment_id);
  const amountBaisa = Number(reservation.data?.amount_baisa);

  // رمز العودة عشوائي، ويُخزَّن مجزَّأً: معامل success في الرابط ليس دليل دفع
  const returnToken = crypto.randomUUID().replace(/-/g, '');
  const returnTokenHash = await sha256(`return:${returnToken}`);

  const baseReturn = Deno.env.get('THAWANI_SUCCESS_URL') ?? 'https://qr.myduby.com/payment/success';
  const baseCancel = Deno.env.get('THAWANI_CANCEL_URL') ?? 'https://qr.myduby.com/payment/cancel';

  const session = await paymentProvider().createSession({
    orderId: String(body.order_id),
    orderNo: Number(body.order_no ?? 0),
    amountBaisa,
    successUrl: `${baseReturn}?rt=${returnToken}`,
    cancelUrl: `${baseCancel}?rt=${returnToken}`,
    metadata: { invoice: invoiceNumber },
  });

  if (!session.ok) {
    await staff.client.rpc('fn_release_invoice', {
      p_payment_id: paymentId,
      p_reason: session.code,
    });
    return err('provider_error', requestId, origin, 'تعذّر إنشاء رابط الدفع، حاول مجددًا');
  }

  const attached = await staff.client.rpc('fn_attach_checkout', {
    p_payment_id: paymentId,
    p_invoice_number: invoiceNumber,
    p_amount: amount,
    p_session_id: session.sessionId,
    p_checkout_url: session.checkoutUrl,
    p_return_token_hash: returnTokenHash,
  });

  if (attached.error) {
    await staff.client.rpc('fn_release_invoice', { p_payment_id: paymentId, p_reason: 'db_error' });
    return err('server_error', requestId, origin);
  }

  return relay(attached, requestId, origin);
}

/** استعلام يدوي: الطبقة الثانية من طبقات تأكيد الدفع الثلاث. */
async function handleVerify(
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const db = serviceClient();

  const { data: payment } = await db
    .from('payments')
    .select('provider_session_id')
    .eq('order_id', String(body.order_id))
    .not('provider_session_id', 'is', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const sessionId = payment?.provider_session_id;
  if (!sessionId) return err('order_not_found', requestId, origin, 'لا جلسة دفع لهذا الطلب');

  const status = await paymentProvider().retrieveSession(sessionId);
  if (!status.ok) return err('provider_error', requestId, origin);

  const { data } = await db.rpc('fn_apply_payment_webhook', {
    p_session_id: sessionId,
    p_provider_status: status.status,
    p_safe_payload: { source: 'manual_verify' },
  });

  const result = data as DbResult;
  return ok({ paid: status.paid, applied: result?.data?.applied ?? false }, requestId, origin);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
