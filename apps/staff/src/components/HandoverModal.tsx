import { useRef, useState } from 'react';
import {
  DEFAULT_HANDOVER_METHOD,
  requiresExceptionReason,
  requiresProof,
  type HandoverMethod,
} from '@duby/shared';
import { callSettlementsApi } from '../lib/settlements-api.js';
import { uploadPhoto } from '../lib/orders-api.js';
import { compressPhoto, type CompressedPhoto } from '../lib/image.js';

const BANK_LABEL = import.meta.env.VITE_BANK_ACCOUNT_LABEL ?? 'حساب دوبي';
const BANK_HINT = import.meta.env.VITE_BANK_ACCOUNT_HINT ?? '';

const METHOD_LABELS: Record<HandoverMethod, string> = {
  bank_deposit: 'إيداع بنكي',
  transfer: 'تحويل',
  office_handover: 'تسليم في المكتب',
  safe_drop: 'إيداع في الخزنة',
};

/**
 * نافذة إيداع النقد.
 *
 * الإيداع البنكي مختار مسبقًا لأنه الطريقة الوحيدة التي يؤكد مبلغها طرف ثالث
 * محايد. البدائل متاحة خلف قائمة مطوية وتتطلب سببًا مكتوبًا يظهر في تقرير
 * الاستثناءات — الاستثناء ممكن لكنه مرئي، وهذا ما يُبقيه استثناءً.
 */
export function HandoverModal({
  settlementId,
  expected,
  onDone,
  onClose,
}: {
  settlementId: string;
  expected: number;
  onDone: () => void;
  onClose: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [amount, setAmount] = useState(expected.toFixed(3));
  const [method, setMethod] = useState<HandoverMethod>(DEFAULT_HANDOVER_METHOD);
  const [reference, setReference] = useState('');
  const [exceptionReason, setExceptionReason] = useState('');
  const [photo, setPhoto] = useState<CompressedPhoto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showMethods, setShowMethods] = useState(false);

  const needsProof = requiresProof(method);
  const needsReason = requiresExceptionReason(method);

  async function submit() {
    setBusy(true);
    setError(null);

    let storagePath: string | null = null;

    if (photo) {
      const urlResult = await callSettlementsApi<{ upload_url: string; storage_path: string }>(
        '/proof-upload-url',
        { content_type: 'image/jpeg', byte_size: photo.blob.size },
      );

      if (!urlResult.ok) {
        setBusy(false);
        setError(`${urlResult.message} (${urlResult.requestId.slice(0, 6)})`);
        return;
      }

      if (!(await uploadPhoto(urlResult.data.upload_url, photo.blob))) {
        setBusy(false);
        setError('تعذّر رفع الإيصال. تحقّق من الشبكة وحاول مجددًا.');
        return;
      }

      storagePath = urlResult.data.storage_path;
    }

    const result = await callSettlementsApi('/handover', {
      settlement_id: settlementId,
      declared_amount: Number(amount),
      handover_method: method,
      handover_reference: reference || null,
      storage_path: storagePath,
      exception_reason: exceptionReason || null,
    });

    setBusy(false);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    onDone();
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="إيداع النقد">
      <div className="modal">
        <header className="modal-header">
          <h3>إيداع نقد اليوم</h3>
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
          <p className="muted">المتوقّع: {expected.toFixed(3)} ر.ع</p>

          <div className="method-row">
            <strong>{METHOD_LABELS[method]}</strong>
            {method === 'bank_deposit' && (
              <span className="muted">
                {BANK_LABEL} {BANK_HINT}
              </span>
            )}
          </div>

          {/* الاستثناء ممكن لكنه ليس في الطريق */}
          <button type="button" className="link" onClick={() => setShowMethods((value) => !value)}>
            {showMethods ? 'إخفاء الطرق' : 'تغيير الطريقة'}
          </button>

          {showMethods && (
            <div className="method-options">
              {(Object.keys(METHOD_LABELS) as HandoverMethod[]).map((option) => (
                <label key={option}>
                  <input
                    type="radio"
                    name="handover-method"
                    value={option}
                    checked={method === option}
                    onChange={() => setMethod(option)}
                  />
                  {METHOD_LABELS[option]}
                </label>
              ))}
            </div>
          )}

          <label htmlFor="declared">المبلغ المُودَع</label>
          <input
            id="declared"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            inputMode="decimal"
          />

          {needsProof && (
            <>
              <label htmlFor="reference">رقم إيصال الإيداع *</label>
              <input
                id="reference"
                value={reference}
                onChange={(event) => setReference(event.target.value)}
                placeholder="DEP-88421"
              />
            </>
          )}

          {needsReason && (
            <>
              <label htmlFor="exception">سبب عدم الإيداع البنكي *</label>
              <input
                id="exception"
                value={exceptionReason}
                onChange={(event) => setExceptionReason(event.target.value)}
                placeholder="البنك مغلق — عطلة"
              />
              {/* المندوب يعرف أن الاستثناء مرئي */}
              <p className="muted">ⓘ سيظهر هذا في تقرير الاستثناءات</p>
            </>
          )}

          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            onChange={async (event) => {
              const file = event.target.files?.[0];
              if (!file) return;
              try {
                setPhoto(await compressPhoto(file));
              } catch {
                setError('تعذّر قراءة الصورة. أعد الالتقاط.');
              }
            }}
          />

          {photo ? (
            <img className="field-photo" src={photo.previewUrl} alt="صورة الإيصال" />
          ) : (
            <div className="field-photo placeholder">
              {needsProof ? 'صورة الإيصال إلزامية' : 'صورة الإثبات (اختيارية)'}
            </div>
          )}

          <button type="button" onClick={() => fileRef.current?.click()} disabled={busy}>
            {photo ? 'التقاط صورة أخرى' : 'التقاط صورة الإيصال'}
          </button>

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
            disabled={
              busy ||
              !amount ||
              (needsProof && (!reference || !photo)) ||
              (needsReason && !exceptionReason)
            }
          >
            {busy ? 'جارٍ الإيداع…' : 'إيداع وتوثيق'}
          </button>
        </footer>
      </div>
    </div>
  );
}
