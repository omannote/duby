import type { ErrorCode } from './errors.js';
import { ERROR_MESSAGES } from './errors.js';

/**
 * غلاف النتيجة الموحّد.
 *
 * حالة العمل المعروفة تُرمَّز في الجسم مع HTTP 200، لا في رمز HTTP. في النظام
 * السابق كانت الأخطاء تعود non-2xx فتبتلعها مكتبة العميل وتعرض
 * «Edge Function returned a non-2xx status code» بلا معلومة قابلة للتشخيص.
 */
export type Ok<T> = { ok: true; data: T; request_id: string };
export type Err = { ok: false; code: ErrorCode; message: string; request_id: string };
export type Result<T> = Ok<T> | Err;

export function ok<T>(data: T, requestId: string): Ok<T> {
  return { ok: true, data, request_id: requestId };
}

export function err(code: ErrorCode, requestId: string, message?: string): Err {
  return { ok: false, code, message: message ?? ERROR_MESSAGES[code], request_id: requestId };
}

export function isOk<T>(result: Result<T>): result is Ok<T> {
  return result.ok;
}

/** معرّف ارتباط قصير يمر عبر كل الطبقات ويُعرض للمستخدم عند الخطأ (ADR-009). */
export function newRequestId(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}
