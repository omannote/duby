-- بنية المخطط: الجداول والأنواع والفهارس موجودة كما وُصفت.
begin;
select plan(25);

-- ── الجداول ───────────────────────────────────────────────────────────────
select has_table('public', t, format('جدول %s موجود', t))
  from unnest(array[
    'staff', 'properties', 'customers', 'customer_qr_tokens',
    'scan_events', 'otp_challenges', 'order_submissions',
    'orders', 'order_photos', 'order_status_history', 'order_status_settings',
    'payments', 'payment_events',
    'cash_settlements', 'cash_collections', 'public_holidays'
  ]) as t;

select has_table('private', 'audit_logs', 'سجل التدقيق في مخطط private');
select has_table('private', 'notification_outbox', 'طابور الإشعارات في مخطط private');

-- ── الأنواع ───────────────────────────────────────────────────────────────
-- delivered محذوفة عمدًا: كانت تعني شيئين مختلفين فأنتجت طلبات عالقة
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'order_status'),
  array['new','confirmed','picked_up','processing','ready','out_for_delivery','completed','cancelled'],
  'حالات الطلب الثماني بالترتيب الصحيح، بلا delivered'
);

select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'staff_role'),
  array['courier','operator','manager','admin'],
  'الأدوار الأربعة مرتبة من المندوب إلى المدير'
);

-- ── الفهارس الحرجة ────────────────────────────────────────────────────────
select has_index('public', 'orders', 'orders_invoice_no_idx', 'رقم الفاتورة فريد');
select has_index('public', 'customer_qr_tokens', 'customer_qr_active_idx', 'رمز فعّال واحد لكل عميل');
select has_index('public', 'order_photos', 'order_photos_kind_idx', 'صورة واحدة من كل نوع');
select has_index('public', 'orders', 'orders_active_idx', 'فهرس الطلبات النشطة حسب العقار');

-- ── إلزامية العقار على مستوى المخطط ───────────────────────────────────────
select col_not_null('public', 'customers', 'property_id', 'العميل لا يوجد بلا عقار');

select * from finish();
rollback;
