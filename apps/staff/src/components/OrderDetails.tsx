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

type NotificationRow = {
  id: number;
  state: 'pending' | 'sending' | 'sent' | 'failed' | 'skipped' | 'dead';
  message: string;
  attempts: number;
  last_error_code: string | null;
  created_at: string;
  sent_at: string | null;
};

const NOTIFICATION_STATES: Record<NotificationRow['state'], string> = {
  pending: 'بانتظار الإرسال',
  sending: 'جارٍ الإرسال',
  sent: 'أُرسل',
  failed: 'فشل — سيُعاد',
  skipped: 'متجاوَز (الإشعار معطّل)',
  dead: 'توقّف بعد المحاولات',
};

const PHOTO_LABELS: Record<string, string> = {
  intake: 'صورة العميل',
  pickup: 'صورة الاستلام',
  delivery: 'صورة التسليم',
  cash_handover: 'إيصال الإيداع',
};

export function OrderDetails({ order, onBack }: { order: Order; onBack: () => void }) {
  const [history, setHistory] = useState<HistoryRow[]>([]);
  const [photos, setPhotos] = useState<PhotoRow[]>([]);
  const [notifications, setNotifications] = useState<NotificationRow[]>([]);
  const [openPhoto, setOpenPhoto] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) return;

    void (async () => {
      const [historyResult, photosResult, notificationsResult] = await Promise.all([
        supabase
          .from('order_status_history')
          .select('id, from_status, to_status, changed_at, reason, staff:changed_by(full_name)')
          .eq('order_id', order.id)
          .order('changed_at'),
        supabase
          .from('order_photos')
          .select('id, kind, storage_path, taken_at')
          .eq('order_id', order.id),
        // الطابور في مخطط private؛ هذه الدالة المنفذ الوحيد إليه
        supabase.rpc('fn_order_notifications', { p_order_id: order.id }),
      ]);

      setHistory((historyResult.data ?? []) as unknown as HistoryRow[]);
      setPhotos((photosResult.data ?? []) as PhotoRow[]);
      setNotifications((notificationsResult.data ?? []) as NotificationRow[]);
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

      <h3 className="section-title">الإشعارات</h3>
      {notifications.length === 0 ? (
        <p className="empty">لا إشعارات.</p>
      ) : (
        <ul className="cards">
          {notifications.map((notification) => (
            <li key={notification.id} className="card">
              <div className="card-main">
                <span>{notification.message}</span>
                <span className="muted">
                  {new Date(notification.created_at).toLocaleString('ar-OM')}
                  {notification.attempts > 0 && ` · ${notification.attempts} محاولة`}
                  {notification.last_error_code && ` · ${notification.last_error_code}`}
                </span>
              </div>
              <span
                className={
                  notification.state === 'sent'
                    ? 'badge-on'
                    : notification.state === 'dead'
                      ? 'badge-off'
                      : 'badge-warn'
                }
              >
                {NOTIFICATION_STATES[notification.state]}
              </span>
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
