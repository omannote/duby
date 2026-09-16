import { ERROR_MESSAGES, type ErrorCode } from '@duby/shared';
import { supabase } from '../supabase.js';

const FUNCTIONS_URL = `${import.meta.env.VITE_SUPABASE_URL ?? ''}/functions/v1/payments`;
const APP_VERSION = import.meta.env.VITE_APP_VERSION ?? 'dev';

export type ApiResult<T> =
  | { ok: true; data: T; requestId: string }
  | { ok: false; code: ErrorCode; message: string; requestId: string };

export async function callPaymentsApi<T>(path: string, body: unknown): Promise<ApiResult<T>> {
  const requestId = crypto.randomUUID().replace(/-/g, '').slice(0, 16);

  if (!supabase) {
    return { ok: false, code: 'server_error', message: 'التطبيق غير مهيّأ', requestId };
  }

  // getSession لا refreshSession: الأخيرة تعيد تركيب الشجرة وتغلق النافذة
  const { data: session } = await supabase.auth.getSession();
  const token = session.session?.access_token;

  if (!token) {
    return { ok: false, code: 'forbidden', message: ERROR_MESSAGES.forbidden, requestId };
  }

  try {
    const response = await fetch(`${FUNCTIONS_URL}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
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
    return {
      ok: false,
      code: 'server_error',
      message: 'تعذّر الاتصال. تحقّق من الشبكة وحاول مجددًا.',
      requestId,
    };
  }
}
