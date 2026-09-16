import type { StaffRole } from '@duby/shared';
import { supabase } from '../supabase.js';
import type { Column, ReportRow } from './csv.js';

/**
 * التقارير قراءة مباشرة من عروض `security_invoker`: لا دالة وسيطة ولا
 * صلاحية أوسع. ما يعود هو ما تسمح به سياسات RLS وحارس الدور داخل العرض
 * نفسه، فالواجهة لا تملك وسيلة لرؤية ما لا يحقّ لصاحب الجلسة رؤيته.
 */
export type ReportSpec = {
  key: string;
  title: string;
  hint?: string;
  view: string;
  columns: Column[];
  order?: { column: string; ascending: boolean };
  limit?: number;
  /** أدنى دور يعيد له العرض صفوفًا. يُستخدم لإخفاء ما لا معنى لعرضه فارغًا. */
  minRole: StaffRole;
};

export type ReportResult = { ok: true; rows: ReportRow[] } | { ok: false; message: string };

export async function loadReport(spec: ReportSpec): Promise<ReportResult> {
  if (!supabase) return { ok: false, message: 'التطبيق غير مهيّأ' };

  let query = supabase.from(spec.view).select(spec.columns.map((c) => c.key).join(', '));

  if (spec.order) {
    query = query.order(spec.order.column, { ascending: spec.order.ascending });
  }

  query = query.limit(spec.limit ?? 500);

  const { data, error } = await query;

  if (error) {
    return { ok: false, message: 'تعذّر تحميل التقرير' };
  }

  return { ok: true, rows: (data ?? []) as unknown as ReportRow[] };
}

export type { Cell, Column, ReportRow } from './csv.js';
export { formatCell, toCsv, downloadCsv } from './csv.js';
