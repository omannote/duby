import { ERROR_MESSAGES, type ErrorCode } from '@duby/shared';

const FUNCTIONS_URL = `${import.meta.env.VITE_SUPABASE_URL ?? ''}/functions/v1/public-qr`;
const ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY ?? '';
const APP_VERSION = import.meta.env.VITE_APP_VERSION ?? 'dev';

export type ApiResult<T> =
  | { ok: true; data: T; requestId: string }
  | { ok: false; code: ErrorCode; message: string; requestId: string };

function newRequestId(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}

/**
 * كل استدعاء يحمل معرّف ارتباط يُعاد في الاستجابة ويُعرض مع رسالة الخطأ،
 * فيتحول بلاغ العميل إلى بحث واحد في السجل بدل جولات تشخيص.
 */
export async function callApi<T>(path: string, body: unknown): Promise<ApiResult<T>> {
  const requestId = newRequestId();

  try {
    const response = await fetch(`${FUNCTIONS_URL}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ANON_KEY}`,
        apikey: ANON_KEY,
        'X-Request-Id': requestId,
        'X-App-Version': APP_VERSION,
      },
      body: JSON.stringify(body),
    });

    const payload = (await response.json()) as
      | { ok: true; data: T; request_id?: string }
      | { ok: false; code: ErrorCode; message?: string; request_id?: string };

    if (payload.ok) {
      return { ok: true, data: payload.data, requestId: payload.request_id ?? requestId };
    }

    return {
      ok: false,
      code: payload.code,
      message: payload.message ?? ERROR_MESSAGES[payload.code] ?? ERROR_MESSAGES.server_error,
      requestId: payload.request_id ?? requestId,
    };
  } catch {
    // انقطاع الشبكة يُميَّز عن خطأ الخادم
    return {
      ok: false,
      code: 'server_error',
      message: 'تعذّر الاتصال. تحقّق من الشبكة وحاول مجددًا.',
      requestId,
    };
  }
}

/** الرفع يذهب إلى التخزين مباشرة، لا عبر الوظيفة. */
export async function uploadPhoto(uploadUrl: string, blob: Blob): Promise<boolean> {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetch(uploadUrl, {
        method: 'PUT',
        headers: { 'Content-Type': 'image/jpeg' },
        body: blob,
      });
      if (response.ok) return true;
    } catch {
      // إعادة محاولة بتراجع قصير قبل عرض زر يدوي
    }

    if (attempt < 2) await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
  }

  return false;
}
