import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/**
 * عميل بصلاحية service_role — يتجاوز RLS، ولا يغادر الخادم إطلاقًا.
 * يُستخدم لاستدعاء الدوال التي تفحص الدور بنفسها.
 */
export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
}

export type StaffIdentity = {
  staffId: string;
  role: string;
  userId: string;
  /**
   * عميل مقيّد بجلسة الموظف.
   *
   * دوال النطاق تُستدعى به لا بـ service_role: الأخير لا يحمل مطالبة sub
   * فـ auth_role() تعيد null وترد كل دالة forbidden (ADR-011). أما التخزين
   * فيحتاج service_role، فتستخدم الوظيفة العميلين معًا لغرضين مختلفين.
   */
  client: SupabaseClient;
};

/**
 * يتحقق من جلسة الموظف ويعيد دوره.
 *
 * `auth_role()` تعيد null للموظف المعطَّل أو المحذوف، فالتعطيل يسري فورًا دون
 * انتظار انتهاء الجلسة.
 */
export async function requireStaff(request: Request): Promise<StaffIdentity | null> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;

  const scoped = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data: user } = await scoped.auth.getUser();
  if (!user?.user) return null;

  const { data: role, error } = await scoped.rpc('auth_role');
  if (error || !role) return null;

  const { data: staffId } = await scoped.rpc('auth_staff_id');
  if (!staffId) return null;

  return { staffId, role, userId: user.user.id, client: scoped };
}
