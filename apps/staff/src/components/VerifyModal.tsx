import { useEffect, useState } from 'react';
import { callSettlementsApi } from '../lib/settlements-api.js';
import { supabase } from '../supabase.js';

/**
 * نافذة الاعتماد عن بُعد.
 *
 * الصورة أولًا: في هذا النموذج يقوم القرار على الإثبات لا على عدّ حضوري،
 * فالإيصال هو ما يُطابَق لا النقد. والشاشة تعمل على الهاتف بنفس كفاءة سطح
 * المكتب لأن المدقّق قد يعتمد من أي مكان.
 */
export function VerifyModal({
  settlement,
  onDone,
  onClose,
}: {
  settlement: {
    id: string;
    courier_name: string;
    business_date: string;
    expected_amount: number;
    declared_amount: number | null;
    handover_method: string | null;
    handover_reference: string | null;
    handover_photo_id: string | null;
  };
  onDone: () => void;
  onClose: () => void;
}) {
  const [confirmed, setConfirmed] = useState(settlement.declared_amount?.toFixed(3) ?? '');
  const [reason, setReason] = useState('');
  const [proofUrl, setProofUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!settlement.handover_photo_id || !supabase) return;

    void (async () => {
      const { data } = await supabase
        .from('order_photos')
        .select('storage_path')
        .eq('id', settlement.handover_photo_id)
        .maybeSingle();

      if (!data?.storage_path) return;

      const result = await callSettlementsApi<{ url: string }>('/proof-url', {
        storage_path: data.storage_path,
      });

      if (result.ok) setProofUrl(result.data.url);
    })();
  }, [settlement.handover_photo_id]);

  const variance = Number(confirmed) - settlement.expected_amount;
  const hasVariance = Number.isFinite(variance) && Math.abs(variance) > 0.0005;

  async function submit() {
    setBusy(true);
    setError(null);

    const result = await callSettlementsApi('/verify', {
      settlement_id: settlement.id,
      confirmed_amount: Number(confirmed),
      variance_reason: reason || null,
    });

    setBusy(false);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    onDone();
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="اعتماد التسوية">
      <div className="modal">
        <header className="modal-header">
          <h3>
            {settlement.courier_name} · {settlement.business_date}
          </h3>
          <button
            type="button"
            className="icon"
            onClick={onClose}
            aria-label="إغلاق"
            disabled={busy}
          >
            ✕
          </button>
        </header>

        <div className="modal-body">
          {proofUrl ? (
            <img className="field-photo" src={proofUrl} alt="إيصال الإيداع" />
          ) : (
            <div className="field-photo placeholder">لا إيصال مرفق</div>
          )}

          <p className="muted">
            {settlement.handover_method === 'bank_deposit'
              ? 'إيداع بنكي'
              : settlement.handover_method}
            {settlement.handover_reference && ` · ${settlement.handover_reference}`}
          </p>

          <dl className="facts">
            <dt>المتوقّع</dt>
            <dd>{settlement.expected_amount.toFixed(3)} ر.ع</dd>
            <dt>المُعلَن</dt>
            <dd>{settlement.declared_amount?.toFixed(3) ?? '—'} ر.ع</dd>
          </dl>

          <label htmlFor="confirmed">المبلغ المؤكَّد من الإثبات</label>
          <input
            id="confirmed"
            value={confirmed}
            onChange={(event) => setConfirmed(event.target.value)}
            inputMode="decimal"
          />

          {hasVariance && (
            <p className={variance < 0 ? 'warn' : 'muted'}>
              الفرق: {variance.toFixed(3)} ر.ع ({variance < 0 ? 'عجز' : 'زيادة'})
            </p>
          )}

          {hasVariance && (
            <>
              <label htmlFor="variance-reason">سبب الفرق *</label>
              <input
                id="variance-reason"
                value={reason}
                onChange={(event) => setReason(event.target.value)}
              />
            </>
          )}

          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
        </div>

        <footer className="modal-footer">
          <button type="button" className="ghost" onClick={onClose} disabled={busy}>
            إلغاء
          </button>
          <button
            type="button"
            onClick={() => void submit()}
            disabled={busy || !confirmed || (hasVariance && reason.trim().length < 3)}
          >
            {busy ? 'جارٍ الاعتماد…' : 'اعتماد التسوية'}
          </button>
        </footer>
      </div>
    </div>
  );
}
