/**
 * مزوّد الدفع خلف واجهة مجرّدة، فيمكن استبداله دون لمس منطق الطلبات.
 *
 * المفتاح السري لا يغادر الخادم. كل نداء لثواني من هنا، ولا شيء منه يصل
 * المتصفح سوى رابط السداد.
 */
export type SessionResult =
  | { ok: true; sessionId: string; checkoutUrl: string }
  | { ok: false; code: string };

export type SessionStatus =
  | { ok: true; status: string; paid: boolean }
  | { ok: false; code: string };

export interface PaymentProvider {
  createSession(input: {
    orderId: string;
    orderNo: number;
    amountBaisa: number;
    successUrl: string;
    cancelUrl: string;
    metadata: Record<string, string>;
  }): Promise<SessionResult>;

  retrieveSession(sessionId: string): Promise<SessionStatus>;

  verifyWebhook(rawBody: string, signature: string | null): Promise<boolean>;
}

const TIMEOUT_MS = 15_000;

async function request(path: string, init: RequestInit): Promise<Response | null> {
  const baseUrl = Deno.env.get('THAWANI_API_BASE_URL');
  const secret = Deno.env.get('THAWANI_SECRET_KEY');
  if (!baseUrl || !secret) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    return await fetch(`${baseUrl}${path}`, {
      ...init,
      signal: controller.signal,
      headers: { 'Content-Type': 'application/json', 'thawani-api-key': secret },
    });
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

export class ThawaniProvider implements PaymentProvider {
  async createSession(input: {
    orderId: string;
    orderNo: number;
    amountBaisa: number;
    successUrl: string;
    cancelUrl: string;
    metadata: Record<string, string>;
  }): Promise<SessionResult> {
    const response = await request('/api/v1/checkout/session', {
      method: 'POST',
      body: JSON.stringify({
        client_reference_id: input.orderId,
        mode: 'payment',
        products: [{
          name: `طلب غسيل QR-${String(input.orderNo).padStart(4, '0')}`,
          quantity: 1,
          unit_amount: input.amountBaisa, // بالبيسة
        }],
        success_url: input.successUrl,
        cancel_url: input.cancelUrl,
        metadata: input.metadata,
      }),
    });

    if (!response) return { ok: false, code: 'provider_timeout' };
    if (!response.ok) return { ok: false, code: `provider_http_${response.status}` };

    const body = await response.json().catch(() => null) as
      | { data?: { session_id?: string } }
      | null;

    const sessionId = body?.data?.session_id;
    if (!sessionId) return { ok: false, code: 'provider_bad_response' };

    const publishable = Deno.env.get('THAWANI_PUBLISHABLE_KEY') ?? '';
    const checkoutBase = Deno.env.get('THAWANI_API_BASE_URL') ?? '';

    return {
      ok: true,
      sessionId,
      checkoutUrl: `${checkoutBase}/pay/${sessionId}?key=${publishable}`,
    };
  }

  async retrieveSession(sessionId: string): Promise<SessionStatus> {
    const response = await request(`/api/v1/checkout/session/${sessionId}`, { method: 'GET' });

    if (!response) return { ok: false, code: 'provider_timeout' };
    if (!response.ok) return { ok: false, code: `provider_http_${response.status}` };

    const body = await response.json().catch(() => null) as
      | { data?: { payment_status?: string } }
      | null;

    const status = body?.data?.payment_status ?? 'unknown';
    return { ok: true, status, paid: status === 'paid' };
  }

  /** التحقق قبل قراءة الجسم، ومقارنة ثابتة الزمن. */
  async verifyWebhook(rawBody: string, signature: string | null): Promise<boolean> {
    const secret = Deno.env.get('THAWANI_WEBHOOK_SECRET');
    if (!secret || !signature) return false;

    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );

    const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
    const expected = Array.from(new Uint8Array(mac))
      .map((byte) => byte.toString(16).padStart(2, '0'))
      .join('');

    return timingSafeEqual(expected, signature.trim().toLowerCase());
  }
}

/** مقارنة لا يكشف زمنها موضع أول اختلاف. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** مزوّد مزيّف للتطوير والاختبار — لا يتصل بشيء. */
export class FakePaymentProvider implements PaymentProvider {
  createSession(): Promise<SessionResult> {
    const sessionId = `fake_${crypto.randomUUID()}`;
    return Promise.resolve({
      ok: true,
      sessionId,
      checkoutUrl: `https://example.invalid/pay/${sessionId}`,
    });
  }

  retrieveSession(): Promise<SessionStatus> {
    return Promise.resolve({ ok: true, status: 'paid', paid: true });
  }

  verifyWebhook(): Promise<boolean> {
    return Promise.resolve(true);
  }
}

export function paymentProvider(): PaymentProvider {
  return Deno.env.get('THAWANI_SECRET_KEY') ? new ThawaniProvider() : new FakePaymentProvider();
}
