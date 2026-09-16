/**
 * غلاف النتيجة الموحّد.
 *
 * حالة العمل المعروفة تعود بـ HTTP 200 والرمز في الجسم. في النظام السابق كانت
 * تعود non-2xx فتبتلعها مكتبة العميل وتعرض
 * «Edge Function returned a non-2xx status code» بلا معلومة قابلة للتشخيص.
 */
import { corsHeaders } from './cors.ts';

export function jsonResponse(body: unknown, origin: string | null, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export function ok(data: unknown, requestId: string, origin: string | null): Response {
  return jsonResponse({ ok: true, data, request_id: requestId }, origin);
}

export function err(
  code: string,
  requestId: string,
  origin: string | null,
  message?: string,
): Response {
  return jsonResponse({ ok: false, code, message, request_id: requestId }, origin);
}

/** معرّف ارتباط يمر عبر كل الطبقات ويُعرض للمستخدم عند الخطأ (ADR-009). */
export function requestIdFrom(request: Request): string {
  const provided = request.headers.get('x-request-id');
  if (provided && /^[a-z0-9-]{8,64}$/i.test(provided)) return provided;
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}
