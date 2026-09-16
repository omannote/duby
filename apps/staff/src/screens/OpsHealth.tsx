import { useCallback, useEffect, useState } from 'react';
import { callRpc } from '../lib/api.js';

/*
 * التقارير تجيب عن «كيف يسير العمل»؛ هذه الشاشة تجيب عن «هل النظام نفسه
 * يعمل». طابور إشعارات متوقف أو مهمة مجدولة صامتة لا يظهران في أي رقم
 * تشغيلي — ويبقيان مخفيين حتى يشتكي عميل.
 */
type Health = {
  notifications: {
    pending: number;
    failed: number;
    dead: number;
    sent_last_hour: number;
    stale_pending: number;
  };
  payments: { stuck: number; paid_last_24h: number; failed_last_24h: number };
  settlements: {
    open: number;
    awaiting_verify: number;
    verify_overdue: number;
    disputed: number;
    bank_unmatched: number;
    undeposited_amount: number;
    exceptions_this_month: number;
    handovers_this_month: number;
  };
  orders: { stale: number; unpaid_invoices: number; today: number };
  journey: { scans_24h: number; otp_success_pct: number | null; conversion_pct: number | null };
  reports: {
    stage_durations_refreshed_at: string | null;
    stage_durations_duration_ms: number | null;
    stage_durations_stale: boolean;
  };
  jobs: {
    name: string;
    schedule: string;
    active: boolean;
    last_status: string | null;
    last_run_at: string | null;
  }[];
  checked_at: string;
};

export function OpsHealth() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const result = await callRpc<Health>('fn_ops_health', {});

    if (result.ok) setHealth(result.data);
    else setError(result.code === 'forbidden' ? 'هذه اللوحة لمدير النظام.' : 'تعذّر قراءة الحالة');
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (error) return <p className="error">{error}</p>;
  if (!health) return <p className="muted">جارٍ التحميل…</p>;

  const n = health.notifications;
  const p = health.payments;
  const s = health.settlements;
  const j = health.journey;

  return (
    <section>
      <header className="screen-header">
        <h2>الصحة التشغيلية</h2>
        <button type="button" className="ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      <h3 className="section-title">آخر ٢٤ ساعة</h3>
      <div className="kpi-grid">
        <Metric label="طلبات اليوم" value={health.orders.today} />
        <Metric label="مسحات" value={j.scans_24h} />
        <Metric label="نجاح الرمز" value={pct(j.otp_success_pct)} />
        <Metric label="التحويل إلى طلب" value={pct(j.conversion_pct)} />
        <Metric label="نجاح الإشعارات" value={pct(n.success_pct_24h)} />
      </div>

      <h3 className="section-title">طابور الإشعارات</h3>
      <div className="kpi-grid">
        <Metric label="بالانتظار" value={n.pending} />
        <Metric label="متعثّرة" value={n.failed} warn={n.failed > 0} />
        {/* «ميتة» تعني استُنفدت محاولاتها: لا تُعاد تلقائيًا وتحتاج تدخّلًا */}
        <Metric label="ميتة" value={n.dead} bad={n.dead > 0} />
        <Metric label="أُرسلت آخر ساعة" value={n.sent_last_hour} />
        <Metric label="عالقة > ٥ دقائق" value={n.stale_pending} bad={n.stale_pending > 0} />
      </div>

      <h3 className="section-title">المدفوعات</h3>
      <div className="kpi-grid">
        <Metric label="معلّقة > ساعة" value={p.stuck} warn={p.stuck > 0} />
        <Metric label="مدفوعة ٢٤ ساعة" value={p.paid_last_24h} />
        <Metric label="فاشلة ٢٤ ساعة" value={p.failed_last_24h} />
      </div>

      <h3 className="section-title">التسويات النقدية</h3>
      <div className="kpi-grid">
        <Metric label="مفتوحة" value={s.open} />
        <Metric label="بانتظار الاعتماد" value={s.awaiting_verify} />
        <Metric label="تجاوزت مهلة الاعتماد" value={s.verify_overdue} bad={s.verify_overdue > 0} />
        <Metric label="متنازع عليها" value={s.disputed} warn={s.disputed > 0} />
        <Metric label="بلا مطابقة بنكية" value={s.bank_unmatched} warn={s.bank_unmatched > 0} />
        <Metric
          label="نقد غير مودَع"
          value={`${Number(s.undeposited_amount).toFixed(3)} ر.ع`}
          warn={Number(s.undeposited_amount) > 0}
        />
        <Metric
          label="استثناءات الإيداع هذا الشهر"
          value={`${s.exceptions_this_month} من ${s.handovers_this_month}`}
          warn={s.exceptions_this_month > 0}
        />
      </div>

      <h3 className="section-title">الطلبات</h3>
      <div className="kpi-grid">
        <Metric label="متوقفة" value={health.orders.stale} warn={health.orders.stale > 0} />
        <Metric label="فواتير غير مدفوعة" value={health.orders.unpaid_invoices} />
      </div>

      <h3 className="section-title">تحديث التقارير</h3>
      <dl className="facts">
        <dt>آخر تحديث لزمن المراحل</dt>
        <dd data-health={health.reports.stage_durations_stale ? 'unreachable' : 'connected'}>
          {health.reports.stage_durations_refreshed_at
            ? new Date(health.reports.stage_durations_refreshed_at).toLocaleString('ar-OM')
            : 'لم يُحدَّث بعد'}
        </dd>
        <dt>زمن التحديث</dt>
        <dd>
          {health.reports.stage_durations_duration_ms === null
            ? '—'
            : `${health.reports.stage_durations_duration_ms} مللي`}
        </dd>
      </dl>

      <h3 className="section-title">المهام المجدولة</h3>
      {health.jobs.length === 0 ? (
        <p className="empty">لا جدولة في هذه البيئة.</p>
      ) : (
        <div className="table-scroll">
          <table className="report-table">
            <thead>
              <tr>
                <th scope="col">المهمة</th>
                <th scope="col">الجدول</th>
                <th scope="col">آخر تشغيل</th>
                <th scope="col">النتيجة</th>
              </tr>
            </thead>
            <tbody>
              {health.jobs.map((job) => (
                <tr key={job.name}>
                  <td>{job.name}</td>
                  <td dir="ltr">{job.schedule}</td>
                  <td>
                    {job.last_run_at ? new Date(job.last_run_at).toLocaleString('ar-OM') : '—'}
                  </td>
                  <td>
                    <span
                      className={
                        job.last_status === 'succeeded'
                          ? 'badge-on'
                          : job.last_status
                            ? 'badge-off'
                            : 'badge-warn'
                      }
                    >
                      {job.last_status ?? 'لم يعمل'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="muted">قُرئت {new Date(health.checked_at).toLocaleString('ar-OM')}</p>
    </section>
  );
}

/** النسبة تغيب حين لا عيّنة أصلًا — والفرق بين «صفر بالمئة» و«لا بيانات» مهم. */
function pct(value: number | null): string {
  return value === null ? '—' : `${Number(value).toFixed(1)}%`;
}

function Metric({
  label,
  value,
  warn,
  bad,
}: {
  label: string;
  value: number | string;
  warn?: boolean;
  bad?: boolean;
}) {
  return (
    <div className="kpi" data-warn={warn ? 'true' : undefined} data-bad={bad ? 'true' : undefined}>
      <span className="kpi-value">{value}</span>
      <span className="kpi-label">{label}</span>
    </div>
  );
}
