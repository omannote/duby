/**
 * تنسيق الخلايا وتصدير CSV. وحدة نقية بلا اعتماد على الشبكة أو المتصفح في
 * منطقها، ليبقى التحييد والاقتباس قابلين للاختبار وحدةً.
 */
export type Cell = string | number | boolean | null;
export type ReportRow = Record<string, Cell>;

export type Column = {
  key: string;
  label: string;
  /** كيف يُعرض الرقم: خام، أو مبلغ بالريال، أو نسبة، أو ساعات. */
  format?: 'amount' | 'percent' | 'hours' | 'datetime' | 'date';
};

export type CsvSpec = { columns: Column[] };

export function formatCell(value: Cell | undefined, format?: Column['format']): string {
  if (value === null || value === undefined) return '—';

  switch (format) {
    case 'amount':
      return `${Number(value).toFixed(3)} ر.ع`;
    case 'percent':
      return `${Number(value).toFixed(1)}%`;
    case 'hours':
      return `${Number(value).toFixed(1)} س`;
    case 'datetime':
      return new Date(String(value)).toLocaleString('ar-OM');
    case 'date':
      return new Date(String(value)).toLocaleDateString('ar-OM');
    default:
      return String(value);
  }
}

/*
 * خلية تبدأ بـ = أو + أو - أو @ يفسّرها Excel صيغةً لا نصًّا. أسماء العملاء
 * تأتي من مدخلات خارجية، فالتصدير بلا تحييد يحوّل التقرير إلى ناقل تنفيذ
 * على جهاز من يفتحه.
 */
function neutralize(text: string): string {
  return /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
}

/*
 * يقبل `undefined` لا `Cell` وحده: عمود معرَّف في المواصفة وغائب عن الصف حالة
 * واقعية (عرض تغيّر، أو صف من نسخة أقدم)، و`noUncheckedIndexedAccess` يكشفها.
 * التسلسل يكتبها خلية فارغة لا يسقطها.
 */
function csvField(value: Cell | undefined): string {
  const text = neutralize(value === null || value === undefined ? '' : String(value));
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function toCsv(spec: CsvSpec, rows: ReportRow[]): string {
  const header = spec.columns.map((c) => csvField(c.label)).join(',');
  const body = rows.map((row) => spec.columns.map((c) => csvField(row[c.key])).join(','));

  // BOM ضروري: بدونه يقرأ Excel العربية على ويندوز رموزًا مشوّهة
  return `\uFEFF${[header, ...body].join('\r\n')}\r\n`;
}

export function downloadCsv(filename: string, csv: string): void {
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');

  anchor.href = url;
  anchor.download = filename;
  anchor.rel = 'noopener';
  document.body.append(anchor);
  anchor.click();
  anchor.remove();

  // الإفراج مؤجّل: الإلغاء الفوري يقطع التنزيل في بعض المتصفحات
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
