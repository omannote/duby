import { supabase } from '../supabase.js';
import type { ErrorCode } from '@duby/shared';

/**
 * نتيجة دالة قاعدة البيانات.
 *
 * الدوال تُستدعى بجلسة الموظف نفسه: هويته مرتبطة بتوقيع JWT فلا تُنتحل،
 * و SECURITY DEFINER تتيح لها الكتابة رغم أن RLS لا يمنح الواجهة أي صلاحية
 * كتابة مباشرة.
 */
export type RpcResult<T> = { ok: true; data: T } | { ok: false; code: ErrorCode; message?: string };

export async function callRpc<T>(
  name: string,
  args: Record<string, unknown>,
): Promise<RpcResult<T>> {
  if (!supabase) return { ok: false, code: 'server_error', message: 'التطبيق غير مهيّأ' };

  const { data, error } = await supabase.rpc(name, args);

  if (error) {
    // 42501 = صلاحية غير كافية على مستوى قاعدة البيانات
    const code: ErrorCode = error.code === '42501' ? 'forbidden' : 'server_error';
    return { ok: false, code, message: error.message };
  }

  return data as RpcResult<T>;
}
