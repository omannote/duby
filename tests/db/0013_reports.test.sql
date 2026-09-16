-- التقارير: الأرقام تطابق استعلامًا مستقلًا، والرؤية تحترم الدور.
begin;
select plan(27);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'operator@t.local'),
  ('a3333333-3333-3333-3333-333333333333', 'manager@t.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد المندوب', 'courier'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد المشغّل', 'operator'),
  ('b3333333-3333-3333-3333-333333333333', 'a3333333-3333-3333-3333-333333333333', 'سعيد المشرف', 'manager');

insert into properties (id, code, name) values
  ('c1111111-1111-1111-1111-111111111111', 'TSTR1', 'برج أ'),
  ('c2222222-2222-2222-2222-222222222222', 'TSTR2', 'برج ب');

insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at) values
  ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
   'أحمد', '+96891234561', '1', '1', 'complete', now()),
  ('d2222222-2222-2222-2222-222222222222', 'c2222222-2222-2222-2222-222222222222',
   'سالم', '+96891234562', '2', '2', 'complete', now());

insert into customers (id, property_id)
values ('d3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111');

-- ثلاثة طلبات: مكتمل مدفوع، وخرج للتوصيل غير مدفوع، وملغي
insert into orders (id, customer_id, property_id, status,
                    pickup_confirmed_at, pickup_confirmed_by,
                    delivery_confirmed_at, delivery_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at,
                    payment_status, payment_method, paid_at, paid_recorded_by) values
  ('f1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
   'c1111111-1111-1111-1111-111111111111', 'completed',
   now() - interval '3 days', 'b1111111-1111-1111-1111-111111111111',
   now() - interval '1 day', 'b1111111-1111-1111-1111-111111111111',
   'INV-R1', 12.500, now() - interval '2 days',
   'paid', 'cash_on_delivery', now() - interval '1 day', 'b1111111-1111-1111-1111-111111111111');

insert into orders (id, customer_id, property_id, status,
                    pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at) values
  ('f2222222-2222-2222-2222-222222222222', 'd2222222-2222-2222-2222-222222222222',
   'c2222222-2222-2222-2222-222222222222', 'out_for_delivery',
   now() - interval '9 days', 'b1111111-1111-1111-1111-111111111111',
   'INV-R2', 7.000, now() - interval '9 days');

insert into orders (id, customer_id, property_id, status, cancelled_at, cancelled_by, cancel_reason)
values ('f3333333-3333-3333-3333-333333333333', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'cancelled', now(),
        'b2222222-2222-2222-2222-222222222222', 'العميل ألغى');

-- مسحات: ثلاث، واحدة اكتملت
insert into scan_events (customer_id, scan_session_id, result, scanned_at,
                         otp_requested_at, verified_at, order_submitted_at) values
  ('d1111111-1111-1111-1111-111111111111', gen_random_uuid(), 'order_submitted', now(),
   now(), now(), now()),
  ('d1111111-1111-1111-1111-111111111111', gen_random_uuid(), 'otp_requested', now(), now(), null, null),
  ('d2222222-2222-2222-2222-222222222222', gen_random_uuid(), 'invalid_qr', now(), null, null, null);

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

set local role authenticated;
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

-- ── المؤشرات تطابق استعلامًا مستقلًا ─────────────────────────────────────
select is(
  (select customers_total from v_dashboard_kpis),
  (select count(*)::int from customers where deleted_at is null),
  'إجمالي العملاء يطابق العدّ المباشر'
);

select is(
  (select customers_complete from v_dashboard_kpis),
  2, 'العملاء المكتملون'
);

select is(
  (select customers_incomplete from v_dashboard_kpis),
  1, 'العملاء غير المكتملين'
);

select is(
  (select orders_total from v_dashboard_kpis),
  3, 'إجمالي الطلبات'
);

select is(
  (select orders_active from v_dashboard_kpis),
  1, 'الطلبات النشطة: ما عدا المكتمل والملغي'
);

select is(
  (select revenue_collected from v_dashboard_kpis),
  12.500::numeric(14,3), 'الإيراد المحصّل يطابق الطلب المدفوع'
);

select is(
  (select revenue_pending from v_dashboard_kpis),
  7.000::numeric(14,3), 'والمعلّق يطابق الفاتورة غير المدفوعة'
);

-- المجموع من التقرير = المجموع من الجدول مباشرة
select is(
  (select revenue_collected + revenue_pending from v_dashboard_kpis),
  (select coalesce(sum(invoice_amount), 0)::numeric(14,3) from orders
    where invoice_number is not null and status <> 'cancelled'),
  'المحصّل + المعلّق = مجموع الفواتير'
);

-- ── حسب العقار ──────────────────────────────────────────────────────────
select is(
  (select orders_total from v_orders_by_property where code = 'TSTR1'),
  2, 'طلبا البرج أ'
);

select is(
  (select revenue from v_orders_by_property where code = 'TSTR1'),
  12.500::numeric(14,3), 'وإيراده'
);

select is(
  (select sum(orders_total)::int from v_orders_by_property),
  (select count(*)::int from orders),
  'مجموع الطلبات حسب العقار = إجمالي الطلبات'
);

-- العقار بلا طلبات يظهر بصفر لا يختفي
select is(
  (select orders_total from v_orders_by_property where code = 'TSTR2'),
  1, 'العقار الثاني يظهر بطلبه'
);

-- ── حسب الحالة ──────────────────────────────────────────────────────────
select is(
  (select sum(orders_count)::int from v_orders_by_status),
  3, 'مجموع الحالات = إجمالي الطلبات'
);

-- ── قمع المسح ───────────────────────────────────────────────────────────
select is(
  (select scans_total from v_scan_funnel where business_date = business_date_of()),
  3, 'المسحات اليوم'
);

select is(
  (select orders_submitted from v_scan_funnel where business_date = business_date_of()),
  1, 'المكتملة منها'
);

select is(
  (select conversion_pct from v_scan_funnel where business_date = business_date_of()),
  33.3::numeric, 'نسبة التحويل محسوبة لا مقدَّرة'
);

select is(
  (select rejected from v_scan_funnel where business_date = business_date_of()),
  1, 'والمرفوضة معدودة'
);

-- ── أعمار الفواتير ───────────────────────────────────────────────────────
select is(
  (select count(*)::int from v_unpaid_aging),
  1, 'فاتورة واحدة غير مدفوعة'
);

select is(
  (select age_bucket from v_unpaid_aging),
  '8-14', 'وعمرها في الشريحة الصحيحة'
);

-- الملغي لا يُحتسب دَينًا
select is(
  (select count(*)::int from v_unpaid_aging where order_id = 'f3333333-3333-3333-3333-333333333333'),
  0, 'الطلب الملغي خارج أعمار الفواتير'
);

-- ── الطلبات المتوقفة ─────────────────────────────────────────────────────
reset role;
update orders set status_changed_at = now() - interval '5 days'
 where id = 'f2222222-2222-2222-2222-222222222222';
set local role authenticated;

select is(
  (select count(*)::int from v_stale_orders),
  1, 'الطلب المتوقف يظهر'
);

select cmp_ok(
  (select hours_in_status from v_stale_orders),
  '>', 100::numeric, 'بعدد ساعاته الفعلي'
);

-- ── حراسة الأدوار ───────────────────────────────────────────────────────
-- المندوب: تشغيلي فقط، بلا مال مجمّع ولا أداء زملاء
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  (select count(*)::int from v_scan_funnel),
  0, 'المندوب لا يرى قمع المسح'
);

select is(
  (select count(*)::int from v_unpaid_aging),
  0, 'ولا أعمار الفواتير'
);

select is(
  (select count(*)::int from v_courier_performance),
  0, 'ولا أداء المندوبين'
);

-- المشغّل يرى المال لا أداء الزملاء
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  (select count(*)::int from v_courier_performance),
  0, 'المشغّل لا يرى أداء المندوبين'
);

select act_as('a3333333-3333-3333-3333-333333333333'::uuid);

select cmp_ok(
  (select count(*)::int from v_courier_performance),
  '>=', 1, 'المشرف يراه'
);

reset role;
select * from finish();
rollback;
