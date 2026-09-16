-- 0022 — التقارير والتحليلات.
--
-- كلها عروض بـ security_invoker فتسري عليها سياسات RLS، مع حارس دور صريح في
-- العروض التي تتجاوز ما يراه الموظف تشغيليًا.
--
-- ملاحظة: `orders` مقروء لكل الموظفين لأن العمل اليومي يتطلبه، فالتقارير
-- المشتقة منه ليست سرًّا. أما ما يخص أداء زميل أو مالًا مجمّعًا فمحروس صراحةً.

-- ── مؤشرات اللوحة ────────────────────────────────────────────────────────
create or replace view v_dashboard_kpis
with (security_invoker = true) as
select
  (select count(*) from customers where deleted_at is null)::int            as customers_total,
  (select count(*) from customers
    where deleted_at is null and profile_status = 'complete')::int          as customers_complete,
  (select count(*) from customers
    where deleted_at is null and profile_status = 'incomplete')::int        as customers_incomplete,
  (select count(*) from properties where deleted_at is null and is_active)::int as properties_active,
  (select count(*) from orders)::int                                        as orders_total,
  (select count(*) from orders
    where business_date_of(created_at) = business_date_of())::int           as orders_today,
  (select count(*) from orders
    where status not in ('completed', 'cancelled'))::int                    as orders_active,
  (select coalesce(sum(invoice_amount), 0) from orders
    where payment_status = 'paid')::numeric(14,3)                           as revenue_collected,
  (select coalesce(sum(invoice_amount), 0) from orders
    where payment_status = 'unpaid' and invoice_number is not null)::numeric(14,3) as revenue_pending
where auth_role() is not null;

-- ── الطلبات حسب الحالة ───────────────────────────────────────────────────
create or replace view v_orders_by_status
with (security_invoker = true) as
select o.status, count(*)::int as orders_count
  from orders o
 group by o.status;

-- ── الطلبات حسب العقار ───────────────────────────────────────────────────
create or replace view v_orders_by_property
with (security_invoker = true) as
select
  p.id as property_id,
  p.code,
  p.name,
  count(o.id)::int                                                    as orders_total,
  count(o.id) filter (where o.status not in ('completed','cancelled'))::int as orders_active,
  count(o.id) filter (where o.status = 'completed')::int              as orders_completed,
  count(o.id) filter (where o.status = 'cancelled')::int              as orders_cancelled,
  coalesce(sum(o.invoice_amount) filter (where o.payment_status = 'paid'), 0)::numeric(14,3)
                                                                      as revenue
from properties p
left join orders o on o.property_id = p.id
where p.deleted_at is null
group by p.id, p.code, p.name;

-- ── قمع المسح ────────────────────────────────────────────────────────────
/*
 * نسبة التحويل من مسح إلى طلب هي المؤشر الذي يكشف تعثّر رحلة العميل: هبوطها
 * يعني أن شيئًا في الطريق يوقف الناس، لا أن الطلبات قلّت.
 */
create or replace view v_scan_funnel
with (security_invoker = true) as
select
  business_date_of(s.scanned_at)                                      as business_date,
  count(*)::int                                                       as scans_total,
  count(*) filter (where s.otp_requested_at is not null)::int         as otp_requested,
  count(*) filter (where s.verified_at is not null)::int              as verified,
  count(*) filter (where s.order_submitted_at is not null)::int       as orders_submitted,
  count(*) filter (where s.result in ('invalid_qr','revoked_qr','inactive_customer',
                                      'inactive_property','blocked'))::int as rejected,
  round(
    100.0 * count(*) filter (where s.order_submitted_at is not null)
    / nullif(count(*), 0), 1)                                         as conversion_pct
from scan_events s
where auth_role_at_least('operator')
group by business_date_of(s.scanned_at);

-- ── الفواتير غير المدفوعة حسب العمر ──────────────────────────────────────
create or replace view v_unpaid_aging
with (security_invoker = true) as
select
  o.id as order_id,
  o.order_no,
  o.invoice_number,
  o.invoice_amount,
  o.invoiced_at,
  p.name as property_name,
  (current_date - o.invoiced_at::date)                                as days_outstanding,
  case
    when current_date - o.invoiced_at::date <= 3  then '0-3'
    when current_date - o.invoiced_at::date <= 7  then '4-7'
    when current_date - o.invoiced_at::date <= 14 then '8-14'
    else '15+'
  end                                                                 as age_bucket
from orders o
join properties p on p.id = o.property_id
where o.payment_status = 'unpaid'
  and o.invoice_number is not null
  and o.status <> 'cancelled'
  and auth_role_at_least('operator');

-- ── الإيرادات حسب طريقة الدفع ────────────────────────────────────────────
create or replace view v_revenue_by_method
with (security_invoker = true) as
select
  business_date_of(o.paid_at)                                         as business_date,
  o.payment_method,
  count(*)::int                                                       as orders_count,
  coalesce(sum(o.invoice_amount), 0)::numeric(14,3)                   as total
from orders o
where o.payment_status = 'paid' and o.paid_at is not null
  and auth_role_at_least('operator')
group by business_date_of(o.paid_at), o.payment_method;

-- ── الطلبات المتوقفة ─────────────────────────────────────────────────────
-- الطلب الذي يجلس في مرحلة أطول من عتبتها لا يُكتشف إلا بتقرير يبحث عنه.
create or replace view v_stale_orders
with (security_invoker = true) as
select
  o.id as order_id,
  o.order_no,
  o.status,
  p.name as property_name,
  c.full_name as customer_name,
  o.status_changed_at,
  round(extract(epoch from (now() - o.status_changed_at)) / 3600, 1)   as hours_in_status
from orders o
join properties p on p.id = o.property_id
join customers c on c.id = o.customer_id
where o.status not in ('completed', 'cancelled')
  and o.status_changed_at < now()
      - make_interval(hours => setting_int('orders.stale_alert_hours', 48));

-- ── أداء المندوبين ───────────────────────────────────────────────────────
-- أداء زميل ليس بيانًا تشغيليًا يوميًا: محروس بـmanager فأعلى.
/*
 * التجميع بعروض جانبية لا بضمّ ثلاثي. ضمّ orders مرتين مع cash_collections
 * على المندوب نفسه يضرب الصفوف ببعضها (استلامات × تسليمات × تحصيلات)،
 * فيمرّ count(distinct) على ملايين الصفوف. القياس على بيانات سنة كاملة
 * (scripts/perf-reports.mjs) أظهر 19.6 ثانية قبل هذه الصياغة.
 */
create or replace view v_courier_performance
with (security_invoker = true) as
select
  st.id        as courier_id,
  st.full_name as courier_name,
  p.pickups,
  d.deliveries,
  c.cash_collected
from staff st
cross join lateral (
  select count(*)::int as pickups
    from orders o where o.pickup_confirmed_by = st.id
) p
cross join lateral (
  select count(*)::int as deliveries
    from orders o where o.delivery_confirmed_by = st.id
) d
cross join lateral (
  select coalesce(sum(cc.amount), 0)::numeric(14,3) as cash_collected
    from cash_collections cc
   where cc.courier_id = st.id and cc.reversed_at is null
) c
where st.deleted_at is null
  and auth_role_at_least('manager');

-- الفهرسان يجعلان العروض الجانبية أعلاه بحثًا مفهرسًا لا مسحًا كاملًا
create index if not exists orders_pickup_by_idx
  on orders(pickup_confirmed_by) where pickup_confirmed_by is not null;
create index if not exists orders_delivery_by_idx
  on orders(delivery_confirmed_by) where delivery_confirmed_by is not null;

grant select on
  v_dashboard_kpis, v_orders_by_status, v_orders_by_property, v_scan_funnel,
  v_unpaid_aging, v_revenue_by_method, v_stale_orders, v_courier_performance
  to authenticated;
