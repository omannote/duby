import { useEffect, useState } from 'react';
import type { StaffRole } from '@duby/shared';
import { supabase } from '../supabase.js';

export type StaffSession = {
  staffId: string;
  fullName: string;
  role: StaffRole;
};

type State =
  | { status: 'loading' }
  | { status: 'signed-out' }
  | {
      status: 'signed-in';
      staff: StaffSession;
    }
  | { status: 'no-profile' };

export function useStaffSession(): State {
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    const client = supabase;
    if (!client) {
      setState({ status: 'signed-out' });
      return;
    }

    let active = true;

    /*
     * تُقرأ هوية الموظف من الجدول لا من JWT: الموظف المعطَّل تعيد له
     * auth_role() قيمة فارغة، فيُرفض فورًا دون انتظار انتهاء جلسته.
     */
    const load = async () => {
      const { data: auth } = await client.auth.getSession();
      if (!active) return;

      if (!auth.session) {
        setState({ status: 'signed-out' });
        return;
      }

      const { data, error } = await client
        .from('staff')
        .select('id, full_name, role')
        .eq('user_id', auth.session.user.id)
        .maybeSingle();

      if (!active) return;

      if (error || !data) {
        setState({ status: 'no-profile' });
        return;
      }

      setState({
        status: 'signed-in',
        staff: { staffId: data.id, fullName: data.full_name, role: data.role },
      });
    };

    void load();

    const { data: listener } = client.auth.onAuthStateChange(() => {
      void load();
    });

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  return state;
}

export async function signOut(): Promise<void> {
  await supabase?.auth.signOut();
}
