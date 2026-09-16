export function DoneStep({ orderNo }: { orderNo: number }) {
  return (
    <div className="step done">
      <div className="check" aria-hidden="true">
        ✓
      </div>
      <h1>تم استلام طلبك</h1>
      <p className="order-no">رقم الطلب {orderNo}</p>
      <p>سنتواصل معك عبر واتساب عند تحديث حالة الطلب.</p>
      <p className="muted">شكرًا لاختيارك دوبي — نظافة تستحق ثقتكم.</p>
    </div>
  );
}
