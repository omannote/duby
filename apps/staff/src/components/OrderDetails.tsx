import { useEffect, useState } from 'react';
import { ORDER_STATUS_LABELS, type OrderStatus } from '@duby/shared';
import { supabase } from '../supabase.js';
import { callOrdersApi } from '../lib/orders-api.js';
import type { Order } from '../screens/Orders.js';

type HistoryRow = {
  id: number;
  from_status: OrderStatus | null;
  to_status: OrderStatus;
  changed_at: string;
  reason: string | null;
  staff: { full_name: string } | null;
};

type PhotoRow = { id: string; kind: string; storage_path: string; taken_at: string };

const PHOTO_LABELS: Record<string, string> = {
  intake: 'صورة العميل',
  pickup: 'صورة الاستلام',
  delivery: 'صورة التسليم',
  cash_handover: 'إيصال الإيداع',
};

export function OrderDetails({ order, onBack }: { order: Order; onBack: () => void }) {
  const [history, setHistory] = useState<HistoryRow[]>([]);
  const [photos, setPhotos] = useState<PhotoRow[]>([]);
  const [openPhoto, setOpenPhoto] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) return;

    void (async () => {
      const [historyResult, photosResult] = await Promise.all([
        supabase
          .from('order_status_history')
          .select('id, from_status, to_status, changed_at, reason, staff:changed_by(full_name)')
          .eq('order_id', order.id)
          .order('changed_at'),
        supabase
          .from('order_photos')
          .select('id, kind, storage_path, taken_at')
          .eq('order_id', order.id),
      ]);

      setHistory((historyResult.data ?? []) as unknown as HistoryRow[]);
      setPhotos((photosResult.data ?? []) as PhotoRow[]);
    })();
  }, [order.id]);

  /* الحاوية خاصة: لا رابط دائم لأي صورة، فقط رابط موقّع لدقيقتين. */
  async function viewPhoto(path: string) {
    const result = await callOrdersApi<{ url: string }>('/photo-url', { storage_path: path });
    if (result.ok) setOpenPhoto(result.data.url);
  }

  return (
    <section>
      <header className="screen-header">
        <h2>QR-{String(order.order_no).padStart(4, '0')}</h2>
        <button type="button" onClick={onBack}>
          رجوع
        </button>
      </header>

      <dl className="facts">
        <dt>العميل</dt>
        <dd>{order.customers?.full_name ?? '—'}</dd>
        <dt>العقار</dt>
        <dd>
          {order.properties?.name}
          {order.customers?.floor_number && ` · ط${order.customers.floor_number}`}
          {order.customers?.apartment_number && ` ش${order.customers.apartment_number}`}
        </dd>
        <dt>الحالة</dt>
        <dd>{ORDER_STATUS_LABELS[order.status]}</dd>
        <dt>الدفع</dt>
        <dd>
          {order.payment_status === 'paid' ? 'مدفوع' : 'غير مدفوع'}
          {order.invoice_amount !== null && ` · ${order.invoice_amount.toFixed(3)} ر.ع`}
        </dd>
      </dl>

      <h3 className="section-title">الصور</h3>
      {photos.length === 0 ? (
        <p className="empty">لا توجد صور.</p>
      ) : (
        <ul className="photo-list">
          {photos.map((photo) => (
            <li key={photo.id}>
              <button type="button" onClick={() => void viewPhoto(photo.storage_path)}>
                {PHOTO_LABELS[photo.kind] ?? photo.kind}
              </button>
            </li>
          ))}
        </ul>
      )}

      <h3 className="section-title">الخط الزمني</h3>
      <ol className="timeline">
        {history.map((row) => (
          <li key={row.id}>
            <span className="timeline-status">{ORDER_STATUS_LABELS[row.to_status]}</span>
            <span className="muted">
              {new Date(row.changed_at).toLocaleString('ar-OM')}
              {row.staff?.full_name && ` · ${row.staff.full_name}`}
            </span>
            {row.reason && <span className="muted">السبب: {row.reason}</span>}
          </li>
        ))}
      </ol>

      {openPhoto && (
        <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="عرض الصورة">
          <div className="modal">
            <header className="modal-header">
              <h3>الصورة</h3>
              <button
                type="button"
                className="icon"
                onClick={() => setOpenPhoto(null)}
                aria-label="إغلاق"
              >
                ✕
              </button>
            </header>
            <div className="modal-body">
              <img className="field-photo" src={openPhoto} alt="صورة الطلب" />
            </div>
            <footer className="modal-footer">
              <button type="button" onClick={() => setOpenPhoto(null)}>
                إغلاق
              </button>
            </footer>
          </div>
        </div>
      )}
    </section>
  );
}
