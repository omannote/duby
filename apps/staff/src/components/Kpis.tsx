import { useEffect, useState } from 'react';
import { supabase } from '../supabase.js';

type Kpi = {
  customers_total: number;
  customers_complete: number;
  customers_incomplete: number;
  properties_active: number;
  orders_total: number;
  orders_today: number;
  orders_active: number;
  revenue_collected: number;
  revenue_pending: number;
};

export function Kpis() {
  const [kpi, setKpi] = useState<Kpi | null>(null);

  useEffect(() => {
    if (!supabase) return;

    void supabase
      .from('v_dashboard_kpis')
      .select('*')
      .maybeSingle()
      .then(({ data }) => setKpi((data as Kpi | null) ?? null));
  }, []);

  if (!kpi) return null;

  return (
    <div className="kpi-grid">
      <Cell label="طلبات اليوم" value={kpi.orders_today} />
      <Cell label="طلبات نشطة" value={kpi.orders_active} />
      <Cell label="إجمالي الطلبات" value={kpi.orders_total} />
      <Cell label="عملاء" value={kpi.customers_total} />
      <Cell
        label="ملفات ناقصة"
        value={kpi.customers_incomplete}
        warn={kpi.customers_incomplete > 0}
      />
      <Cell label="عقارات فعّالة" value={kpi.properties_active} />
      <Cell label="محصّل" value={`${Number(kpi.revenue_collected).toFixed(3)} ر.ع`} />
      <Cell
        label="معلّق"
        value={`${Number(kpi.revenue_pending).toFixed(3)} ر.ع`}
        warn={Number(kpi.revenue_pending) > 0}
      />
    </div>
  );
}

function Cell({ label, value, warn }: { label: string; value: number | string; warn?: boolean }) {
  return (
    <div className="kpi" data-warn={warn ? 'true' : undefined}>
      <span className="kpi-value">{value}</span>
      <span className="kpi-label">{label}</span>
    </div>
  );
}
