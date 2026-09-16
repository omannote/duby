import { useCallback, useEffect, useState } from 'react';
import {
  ORDER_STATUS_LABELS,
  canCancel,
  isFinal,
  nextStatus,
  type OrderStatus,
} from '@duby/shared';
import { supabase } from '../supabase.js';
import { callOrdersApi } from '../lib/orders-api.js';
import { FieldStepModal } from '../components/FieldStepModal.js';
import { InvoiceModal } from '../components/InvoiceModal.js';
import { callPaymentsApi } from '../lib/payments-api.js';
import { OrderDetails } from '../components/OrderDetails.js';

export type Order = {
  id: string;
  order_no: number;
  status: OrderStatus;
  payment_status: 'unpaid' | 'paid' | 'refunded';
  invoice_amount: number | null;
  created_at: string;
  property_id: string;
  customers: {
    full_name: string | null;
    floor_number: string | null;
    apartment_number: string | null;
  } | null;
  properties: {
    id: string;
    name: string;
    latitude: number | null;
    longitude: number | null;
  } | null;
};

const ACTIVE_STATUSES: OrderStatus[] = [
  'new',
  'confirmed',
  'picked_up',
  'processing',
  'ready',
  'out_for_delivery',
];

export function Orders() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [tab, setTab] = useState<string>('all');
  const [error, setError] = useState<string | null>(null);
  const [fieldStep, setFieldStep] = useState<{
    orderId: string;
    step: 'pickup' | 'delivery';
  } | null>(null);
  const [details, setDetails] = useState<Order | null>(null);
  const [invoiceFor, setInvoiceFor] = useState<Order | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!supabase) return;

    const { data, error: loadError } = await supabase
      .from('orders')
      .select(
        'id, order_no, status, payment_status, invoice_amount, created_at, property_id, customers(full_name, floor_number, apartment_number), properties(id, name, latitude, longitude)',
      )
      .order('created_at', { ascending: false })
      .limit(300);

    if (loadError) setError('تعذّر تحميل الطلبات');
    else setOrders((data ?? []) as unknown as Order[]);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function advance(order: Order) {
    const next = nextStatus(order.status);
    if (!next) return;

    // الاستلام والتسليم لا يحدثان بضغطة زر: يفتحان نافذة المسح والصورة
    if (next.kind === 'field') {
      setFieldStep({
        orderId: order.id,
        step: order.status === 'confirmed' ? 'pickup' : 'delivery',
      });
      return;
    }

    setBusyId(order.id);
    setError(null);

    const result = await callOrdersApi('/advance', {
      order_id: order.id,
      expected_status: order.status,
      to_status: next.to,
    });

    setBusyId(null);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      // تعارض موظفَين: نعيد التحميل لتظهر الحالة الفعلية
      if (result.code === 'stale_state') await load();
      return;
    }

    await load();
  }

  async function cancel(order: Order) {
    const reason = window.prompt('سبب إلغاء الطلب؟');
    if (!reason || reason.trim().length < 3) return;

    setBusyId(order.id);
    const result = await callOrdersApi('/cancel', { order_id: order.id, reason });
    setBusyId(null);

    if (!result.ok) setError(`${result.message} (${result.requestId.slice(0, 6)})`);
    else await load();
  }

  /** يسجّله المندوب الذي استلم المبلغ؛ يُقيَّد في تسويته اليومية باسمه. */
  async function recordCash(order: Order) {
    if (!window.confirm(`تأكيد استلام ${order.invoice_amount?.toFixed(3)} ر.ع نقدًا؟`)) return;

    setBusyId(order.id);
    const result = await callPaymentsApi('/cash', { order_id: order.id });
    setBusyId(null);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    await load();
  }

  /** الطبقة الثانية من تأكيد الدفع: استعلام يدوي حين يتأخر الـwebhook. */
  async function verifyPayment(order: Order) {
    setBusyId(order.id);
    const result = await callPaymentsApi<{ paid: boolean }>('/verify', { order_id: order.id });
    setBusyId(null);

    if (!result.ok) {
      setError(`${result.message} (${result.requestId.slice(0, 6)})`);
      return;
    }

    if (!result.data.paid) setError('لم يُسجَّل الدفع لدى ثواني بعد.');
    await load();
  }

  const active = orders.filter((order) => ACTIVE_STATUSES.includes(order.status));
  const archived = orders.filter((order) => isFinal(order.status));

  const properties = [
    ...new Map(
      active
        .filter((order) => order.properties)
        .map((order) => [order.properties!.id, order.properties!]),
    ).values(),
  ];

  const visible =
    tab === 'archive'
      ? archived
      : tab === 'all'
        ? active
        : active.filter((order) => order.property_id === tab);

  if (details) {
    return <OrderDetails order={details} onBack={() => setDetails(null)} />;
  }

  return (
    <section>
      <header className="screen-header">
        <h2>الطلبات</h2>
        <button type="button" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {/* تبويب لكل عقار: الطلبات مجمّعة كما يعمل المندوب فعلًا */}
      <div className="tabs" role="tablist">
        <button type="button" role="tab" data-active={tab === 'all'} onClick={() => setTab('all')}>
          الكل ({active.length})
        </button>
        {properties.map((property) => (
          <button
            key={property.id}
            type="button"
            role="tab"
            data-active={tab === property.id}
            onClick={() => setTab(property.id)}
          >
            {property.name}
          </button>
        ))}
        <button
          type="button"
          role="tab"
          data-active={tab === 'archive'}
          onClick={() => setTab('archive')}
        >
          الأرشيف ({archived.length})
        </button>
      </div>

      {tab !== 'all' && tab !== 'archive' && (
        <PropertyLocation property={properties.find((item) => item.id === tab) ?? null} />
      )}

      {visible.length === 0 ? (
        <p className="empty">لا توجد طلبات في هذا التبويب.</p>
      ) : (
        <ul className="cards">
          {visible.map((order) => (
            <OrderCard
              key={order.id}
              order={order}
              busy={busyId === order.id}
              onAdvance={() => void advance(order)}
              onCancel={() => void cancel(order)}
              onOpen={() => setDetails(order)}
              onRecordCash={() => void recordCash(order)}
              onVerifyPayment={() => void verifyPayment(order)}
            />
          ))}
        </ul>
      )}

      {invoiceFor && (
        <InvoiceModal
          orderId={invoiceFor.id}
          orderNo={invoiceFor.order_no}
          onClose={() => setInvoiceFor(null)}
          onDone={async () => {
            setInvoiceFor(null);
            await load();
          }}
        />
      )}

      {fieldStep && (
        <FieldStepModal
          orderId={fieldStep.orderId}
          step={fieldStep.step}
          onClose={() => setFieldStep(null)}
          onDone={async () => {
            setFieldStep(null);
            await load();
          }}
        />
      )}
    </section>
  );
}

function PropertyLocation({
  property,
}: {
  property: { name: string; latitude: number | null; longitude: number | null } | null;
}) {
  if (!property?.latitude || !property.longitude) return null;

  return (
    <a
      className="location-link"
      href={`https://www.google.com/maps?q=${property.latitude},${property.longitude}`}
      target="_blank"
      rel="noreferrer noopener"
    >
      فتح موقع {property.name} في الخرائط
    </a>
  );
}

function OrderCard({
  order,
  busy,
  onAdvance,
  onCancel,
  onOpen,
  onRecordCash,
  onVerifyPayment,
}: {
  order: Order;
  busy: boolean;
  onAdvance: () => void;
  onCancel: () => void;
  onOpen: () => void;
  onRecordCash: () => void;
  onVerifyPayment: () => void;
}) {
  const next = nextStatus(order.status);
  const unpaidDelivery = order.status === 'out_for_delivery' && order.payment_status !== 'paid';

  return (
    <li className="card order-card">
      <button type="button" className="card-main plain" onClick={onOpen}>
        <strong>
          QR-{String(order.order_no).padStart(4, '0')} · {order.customers?.full_name ?? 'عميل'}
        </strong>
        <span className="muted">
          {order.properties?.name}
          {order.customers?.floor_number && ` · ط${order.customers.floor_number}`}
          {order.customers?.apartment_number && ` ش${order.customers.apartment_number}`}
        </span>
        <span className="badges">
          <span className={`status status-${order.status}`}>
            {ORDER_STATUS_LABELS[order.status]}
          </span>
          <span className={order.payment_status === 'paid' ? 'badge-on' : 'badge-warn'}>
            {order.payment_status === 'paid' ? 'مدفوع' : 'غير مدفوع'}
          </span>
        </span>
      </button>

      <div className="card-actions">
        {/* زر واحد يعرض الوجهة لا الحالة الحالية — لا قائمة منسدلة */}
        {next && (
          <button type="button" onClick={onAdvance} disabled={busy || unpaidDelivery}>
            {next.kind === 'field' ? 'تأكيد بالمسح' : `التالي: ${ORDER_STATUS_LABELS[next.to]}`}
          </button>
        )}

        {canCancel(order.status) && (
          <button type="button" className="ghost" onClick={onCancel} disabled={busy}>
            إلغاء
          </button>
        )}

        {isFinal(order.status) && <span className="muted">لا إجراءات — حالة نهائية</span>}
      </div>

      {/*
       * البوابة: الزر معطّل، والسبب ظاهر، والبدائل حاضرة. القاعدة نفسها
       * مفروضة في الدالة وفي قيد CHECK — ثلاث طبقات مستقلة.
       */}
      {unpaidDelivery && (
        <div className="payment-gate">
          <p className="warn">لا يمكن التسليم قبل تسجيل الدفع.</p>
          <div className="card-actions">
            <button type="button" className="ghost" onClick={onVerifyPayment} disabled={busy}>
              تحقق من ثواني
            </button>
            <button type="button" onClick={onRecordCash} disabled={busy}>
              استلمت المبلغ نقدًا
            </button>
          </div>
        </div>
      )}
    </li>
  );
}
