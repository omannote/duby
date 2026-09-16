import { useCallback, useEffect, useMemo, useState } from 'react';
import { ORDER_STATUS_LABELS, atLeast, type StaffRole } from '@duby/shared';
import { REPORT_SPECS } from '../lib/report-specs.js';
import {
  downloadCsv,
  formatCell,
  loadReport,
  toCsv,
  type Cell,
  type ReportRow,
  type ReportSpec,
} from '../lib/reports-api.js';
import { Kpis } from '../components/Kpis.js';

/** قيم مُخزّنة بالإنجليزية تُعرض بالعربية. العرض فقط — التصدير يحمل القيمة الخام. */
const VALUE_LABELS: Record<string, string> = {
  ...ORDER_STATUS_LABELS,
  cash_on_delivery: 'نقدًا عند التسليم',
  thawani: 'ثواني (بطاقة)',
  manual_cash: 'نقدي مسجَّل يدويًا',
};

function display(column: string, value: Cell, format?: string): string {
  if (typeof value === 'string' && VALUE_LABELS[value]) return VALUE_LABELS[value];
  return formatCell(value, format as never);
}

export function Reports({ role }: { role: StaffRole }) {
  const visible = useMemo(() => REPORT_SPECS.filter((spec) => atLeast(role, spec.minRole)), [role]);
  const [active, setActive] = useState(visible[0]?.key ?? '');
  const spec = visible.find((s) => s.key === active) ?? visible[0];

  return (
    <section>
      <header className="screen-header">
        <h2>التقارير</h2>
      </header>

      <Kpis />

      <nav className="tabs" aria-label="التقارير">
        {visible.map((item) => (
          <button
            key={item.key}
            type="button"
            data-active={item.key === active}
            onClick={() => setActive(item.key)}
          >
            {item.title}
          </button>
        ))}
      </nav>

      {spec && <ReportTable spec={spec} />}
    </section>
  );
}

function ReportTable({ spec }: { spec: ReportSpec }) {
  const [rows, setRows] = useState<ReportRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setRows(null);
    setError(null);

    const result = await loadReport(spec);

    if (result.ok) setRows(result.rows);
    else setError(result.message);
  }, [spec]);

  useEffect(() => {
    void load();
  }, [load]);

  /*
   * التصدير يُسلسل الصفوف التي عادت بجلسة هذا الموظف — لا استعلام ثانٍ ولا
   * صلاحية أوسع. فما لا يظهر على الشاشة لا يمكن أن يظهر في الملف.
   */
  const exportCsv = () => {
    if (!rows) return;
    const stamp = new Date().toISOString().slice(0, 10);
    downloadCsv(`duby-${spec.key}-${stamp}.csv`, toCsv(spec, rows));
  };

  return (
    <div className="report">
      <div className="report-head">
        <div>
          <h3>{spec.title}</h3>
          {spec.hint && <p className="muted">{spec.hint}</p>}
        </div>
        <div className="report-actions no-print">
          <button type="button" className="ghost" onClick={() => void load()}>
            تحديث
          </button>
          <button type="button" className="ghost" onClick={exportCsv} disabled={!rows?.length}>
            تصدير CSV
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {!rows && !error && <p className="muted">جارٍ التحميل…</p>}
      {rows?.length === 0 && <p className="empty">لا بيانات في هذا التقرير.</p>}

      {rows && rows.length > 0 && (
        <div className="table-scroll">
          <table className="report-table">
            <thead>
              <tr>
                {spec.columns.map((column) => (
                  <th key={column.key} scope="col">
                    {column.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <tr key={index}>
                  {spec.columns.map((column) => (
                    <td key={column.key}>{display(column.key, row[column.key], column.format)}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {rows && rows.length > 0 && <p className="muted">{rows.length} سطرًا</p>}
    </div>
  );
}
