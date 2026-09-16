import { useState } from 'react';
import { omrAmount } from '@duby/shared';
import { callPaymentsApi } from '../lib/payments-api.js';

/**
 * نافذة الفاتورة عند الخروج للتوصيل.
 *
 * فشل المزود لا يترك أثرًا: الحجز يُحرَّر فلا فاتورة ولا انتقال حالة.
 */
export function InvoiceModal({
  orderId,
  orderNo,
  onDone,
  onClose,
}: {
  orderId: string;
  orderNo: number;
  onDone: () => void;
  onClose: () => void;
}) {
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    const value = Number(amount);
    const parsed = omrAmount.safeParse(value);

    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'قيمة الفاتورة غير صحيحة');
      return;
    }

    setBusy(true);
    setError(null);

    const result = await callPaymentsApi('/invoice', {
      order_id: orderId,
      order_no: orderNo,
      invoice_number: invoiceNumber.trim(),
      amount: value,
    });

    setBusy(false);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    onDone();
  }

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="إنشاء الفاتورة">
      <div className="modal">
        <header className="modal-header">
          <h3>فاتورة QR-{String(orderNo).padStart(4, '0')}</h3>
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
          <label htmlFor="invoice-number">رقم الفاتورة</label>
          <input
            id="invoice-number"
            value={invoiceNumber}
            onChange={(event) => setInvoiceNumber(event.target.value)}
            placeholder="INV-2026-0042"
          />

          <label htmlFor="invoice-amount">القيمة بالريال العماني</label>
          <input
            id="invoice-amount"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            inputMode="decimal"
            placeholder="4.500"
          />

          <p className="muted">سيُرسل رابط الدفع إلى العميل مع إشعار تحديث الحالة.</p>

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
            disabled={busy || !invoiceNumber.trim() || !amount}
          >
            {busy ? 'جارٍ إنشاء رابط الدفع…' : 'إنشاء الفاتورة'}
          </button>
        </footer>
      </div>
    </div>
  );
}
