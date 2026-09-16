import { useCallback, useEffect, useState } from 'react';
import { atLeast, type StaffRole } from '@duby/shared';
import { supabase } from '../supabase.js';
import { callSettlementsApi } from '../lib/settlements-api.js';
import { HandoverModal } from '../components/HandoverModal.js';
import { VerifyModal } from '../components/VerifyModal.js';

type Settlement = {
  id: string;
  business_date: string;
  state: 'open' | 'handed_over' | 'verified' | 'disputed';
  expected_amount: number;
  declared_amount: number | null;
  confirmed_amount: number | null;
  variance: number | null;
  handover_method: string | null;
  handover_reference: string | null;
  handover_at: string | null;
};

type Awaiting = Settlement & {
  courier_name: string;
  handover_photo_id: string | null;
  hours_since_handover: number;
  sla_breached: boolean;
};

type Collection = {
  id: string;
  amount: number;
  collected_at: string;
  orders: { order_no: number } | null;
};

const STATE_LABELS: Record<Settlement['state'], string> = {
  open: 'مفتوحة',
  handed_over: 'بانتظار الاعتماد',
  verified: 'معتمدة',
  disputed: 'متنازع عليها',
};

type Tab = 'mine' | 'awaiting' | 'pending' | 'unmatched';

export function Cash({ role, staffId }: { role: StaffRole; staffId: string }) {
  const [tab, setTab] = useState<Tab>(atLeast(role, 'operator') ? 'awaiting' : 'mine');
  const [mine, setMine] = useState<Settlement[]>([]);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [awaiting, setAwaiting] = useState<Awaiting[]>([]);
  const [pending, setPending] = useState<Record<string, unknown>[]>([]);
  const [unmatched, setUnmatched] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [handoverFor, setHandoverFor] = useState<Settlement | null>(null);
  const [verifyFor, setVerifyFor] = useState<Awaiting | null>(null);

  const isAuditor = atLeast(role, 'operator');

  const load = useCallback(async () => {
    if (!supabase) return;

    const [mineResult, collectionsResult] = await Promise.all([
      supabase
        .from('cash_settlements')
        .select(
          'id, business_date, state, expected_amount, declared_amount, confirmed_amount, variance, handover_method, handover_reference, handover_at',
        )
        .eq('courier_id', staffId)
        .order('business_date', { ascending: false })
        .limit(30),
      supabase
        .from('cash_collections')
        .select('id, amount, collected_at, orders(order_no)')
        .eq('courier_id', staffId)
        .is('reversed_at', null)
        .order('collected_at', { ascending: false })
        .limit(50),
    ]);

    if (mineResult.error) setError('تعذّر تحميل التسويات');
    else setMine((mineResult.data ?? []) as Settlement[]);

    setCollections((collectionsResult.data ?? []) as unknown as Collection[]);

    if (isAuditor) {
      const [awaitingResult, pendingResult, unmatchedResult] = await Promise.all([
        supabase.from('v_awaiting_verification').select('*').order('handover_at'),
        supabase.from('v_pending_cash').select('*').order('oldest_business_date'),
        supabase.from('v_unmatched_deposits').select('*').order('business_date'),
      ]);

      setAwaiting((awaitingResult.data ?? []) as unknown as Awaiting[]);
      setPending((pendingResult.data ?? []) as Record<string, unknown>[]);
      setUnmatched((unmatchedResult.data ?? []) as Record<string, unknown>[]);
    }
  }, [staffId, isAuditor]);

  useEffect(() => {
    void load();
  }, [load]);

  /** كشف الحساب هو الحكم النهائي، لا الصورة ولا الاعتماد اليومي. */
  async function matchBank(settlementId: string) {
    const reference = window.prompt('المرجع البنكي من كشف الحساب؟');
    if (!reference || reference.trim().length < 3) return;

    const result = await callSettlementsApi('/match-bank', {
      settlement_id: settlementId,
      bank_reference: reference,
    });

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    await load();
  }

  const openSettlement = mine.find((settlement) => settlement.state === 'open');

  return (
    <section>
      <header className="screen-header">
        <h2>الصندوق</h2>
        <button type="button" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <div className="tabs" role="tablist">
        <button
          type="button"
          role="tab"
          data-active={tab === 'mine'}
          onClick={() => setTab('mine')}
        >
          تسويتي
        </button>
        {isAuditor && (
          <>
            <button
              type="button"
              role="tab"
              data-active={tab === 'awaiting'}
              onClick={() => setTab('awaiting')}
            >
              بانتظار الاعتماد ({awaiting.length})
            </button>
            <button
              type="button"
              role="tab"
              data-active={tab === 'pending'}
              onClick={() => setTab('pending')}
            >
              غير مودَع ({pending.length})
            </button>
            <button
              type="button"
              role="tab"
              data-active={tab === 'unmatched'}
              onClick={() => setTab('unmatched')}
            >
              المطابقة البنكية ({unmatched.length})
            </button>
          </>
        )}
      </div>

      {tab === 'mine' && (
        <>
          {openSettlement ? (
            <div className="settlement-summary">
              <span className="muted">المتوقّع بذمتك</span>
              <strong className="big-amount">
                {openSettlement.expected_amount.toFixed(3)} ر.ع
              </strong>
              <span className="muted">من {collections.length} تحصيلات</span>
              <button type="button" onClick={() => setHandoverFor(openSettlement)}>
                إيداع النقد
              </button>
            </div>
          ) : (
            <p className="empty">لا نقد غير مودَع.</p>
          )}

          <ul className="cards">
            {collections.map((collection) => (
              <li key={collection.id} className="card">
                <div className="card-main">
                  <strong>QR-{String(collection.orders?.order_no ?? 0).padStart(4, '0')}</strong>
                  <span className="muted">
                    {new Date(collection.collected_at).toLocaleString('ar-OM')}
                  </span>
                </div>
                <span>{collection.amount.toFixed(3)} ر.ع</span>
              </li>
            ))}
          </ul>

          <h3 className="section-title">تسوياتي السابقة</h3>
          <ul className="cards">
            {mine.map((settlement) => (
              <li key={settlement.id} className="card">
                <div className="card-main">
                  <strong>{settlement.business_date}</strong>
                  <span className="muted">
                    متوقّع {settlement.expected_amount.toFixed(3)}
                    {settlement.confirmed_amount !== null &&
                      ` · مؤكَّد ${settlement.confirmed_amount.toFixed(3)}`}
                  </span>
                </div>
                <span className={settlement.state === 'verified' ? 'badge-on' : 'badge-warn'}>
                  {STATE_LABELS[settlement.state]}
                </span>
              </li>
            ))}
          </ul>
        </>
      )}

      {tab === 'awaiting' && (
        <ul className="cards">
          {awaiting.length === 0 && <p className="empty">لا تسويات بانتظار الاعتماد.</p>}
          {awaiting.map((settlement) => (
            <li key={settlement.id} className="card">
              <div className="card-main">
                <strong>{settlement.courier_name}</strong>
                <span className="muted">
                  {settlement.business_date} · متوقّع {settlement.expected_amount.toFixed(3)} ·
                  مُعلَن {settlement.declared_amount?.toFixed(3)}
                </span>
                {/* التأخير هنا على المدقّق لا على المندوب */}
                <span className={settlement.sla_breached ? 'badge-off' : 'muted'}>
                  منذ {settlement.hours_since_handover} ساعة
                </span>
              </div>
              <button type="button" onClick={() => setVerifyFor(settlement)}>
                اعتماد
              </button>
            </li>
          ))}
        </ul>
      )}

      {tab === 'pending' && <ReportList rows={pending} empty="لا نقد غير مودَع." />}

      {/* التقرير قابل للعمل لا للقراءة فقط: المطابقة الأسبوعية تتم من هنا */}
      {tab === 'unmatched' && (
        <ReportList
          rows={unmatched}
          empty="لا إيداعات بلا مطابقة."
          actionLabel="وسم المطابقة"
          onAction={(row) => void matchBank(String(row.id))}
        />
      )}

      {handoverFor && (
        <HandoverModal
          settlementId={handoverFor.id}
          expected={handoverFor.expected_amount}
          onClose={() => setHandoverFor(null)}
          onDone={async () => {
            setHandoverFor(null);
            await load();
          }}
        />
      )}

      {verifyFor && (
        <VerifyModal
          settlement={verifyFor}
          onClose={() => setVerifyFor(null)}
          onDone={async () => {
            setVerifyFor(null);
            await load();
          }}
        />
      )}
    </section>
  );
}

function ReportList({
  rows,
  empty,
  actionLabel,
  onAction,
}: {
  rows: Record<string, unknown>[];
  empty: string;
  actionLabel?: string;
  onAction?: (row: Record<string, unknown>) => void;
}) {
  if (rows.length === 0) return <p className="empty">{empty}</p>;

  return (
    <ul className="cards">
      {rows.map((row, index) => (
        <li key={index} className="card">
          <div className="card-main">
            <strong>{String(row.courier_name ?? '')}</strong>
            <span className="muted">
              {Object.entries(row)
                .filter(([key]) => key !== 'courier_name' && key !== 'courier_id' && key !== 'id')
                .map(([key, value]) => `${labelFor(key)}: ${formatValue(value)}`)
                .join(' · ')}
            </span>
          </div>
          <div className="card-actions">
            {row.blocked === true && <span className="badge-off">محجوب</span>}
            {row.sla_breached === true && <span className="badge-off">تجاوز المهلة</span>}
            {actionLabel && onAction && (
              <button type="button" onClick={() => onAction(row)}>
                {actionLabel}
              </button>
            )}
          </div>
        </li>
      ))}
    </ul>
  );
}

const LABELS: Record<string, string> = {
  open_settlements: 'تسويات مفتوحة',
  oldest_business_date: 'أقدم تاريخ',
  unhanded_amount: 'المبلغ',
  working_days_unhanded: 'أيام عمل',
  business_date: 'التاريخ',
  confirmed_amount: 'المؤكَّد',
  handover_reference: 'رقم الإيصال',
  days_unmatched: 'أيام بلا مطابقة',
};

function labelFor(key: string): string {
  return LABELS[key] ?? key;
}

function formatValue(value: unknown): string {
  if (typeof value === 'boolean') return value ? 'نعم' : 'لا';
  if (typeof value === 'number') return String(value);
  return String(value ?? '');
}
