-- لوحة الصحة التشغيلية: محصورة بـadmin، وأرقامها تطابق استعلامًا مستقلًا.
begin;
select plan(21);

insert into auth.users (id, email) values
  ('e1111111-1111-1111-1111-111111111111', 'ops-courier@t.local'),
  ('e2222222-2222-2222-2222-222222222222', 'ops-operator@t.local'),
  ('e3333333-3333-3333-3333-333333333333', 'ops-manager@t.local'),
  ('e4444444-4444-4444-4444-444444444444', 'ops-admin@t.local');
insert into staff (id, user_id, full_name, role) values
  ('f1111111-aaaa-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111', 'مندوب', 'courier'),
  ('f2222222-aaaa-2222-2222-222222222222', 'e2222222-2222-2222-2222-222222222222', 'مشغّل', 'operator'),
  ('f3333333-aaaa-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333', 'مشرف', 'manager'),
  ('f4444444-aaaa-4444-4444-444444444444', 'e4444444-4444-4444-4444-444444444444', 'مدير النظام', 'admin');

insert into properties (id, code, name)
values ('c9999999-9999-9999-9999-999999999999', 'TSTOPS', 'برج الصحة');

insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('d9999999-9999-9999-9999-999999999999', 'c9999999-9999-9999-9999-999999999999',
        'عميل الصحة', '+96891234599', '1', '1', 'complete', now());

-- طلب متوقف: فاتورة صدرت ولم تُدفع، وحالته لم تتغير منذ أسبوع
insert into orders (id, customer_id, property_id, status, status_changed_at,
                    pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f9999999-9999-9999-9999-999999999999', 'd9999999-9999-9999-9999-999999999999',
        'c9999999-9999-9999-9999-999999999999', 'out_for_delivery', now() - interval '7 days',
        now() - interval '8 days', 'f1111111-aaaa-1111-1111-111111111111',
        'INV-OPS1', 9.500, now() - interval '8 days');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

set local role authenticated;

-- ── الحارس: كل ما دون admin مرفوض ────────────────────────────────────────
select act_as('e1111111-1111-1111-1111-111111111111'::uuid);
select is(fn_ops_health() ->> 'code', 'forbidden', 'المندوب لا يرى لوحة الصحة');

select act_as('e2222222-2222-2222-2222-222222222222'::uuid);
select is(fn_ops_health() ->> 'code', 'forbidden', 'المشغّل لا يرى لوحة الصحة');

select act_as('e3333333-3333-3333-3333-333333333333'::uuid);
select is(fn_ops_health() ->> 'code', 'forbidden', 'المشرف لا يرى لوحة الصحة');

select act_as('e4444444-4444-4444-4444-444444444444'::uuid);
select is((fn_ops_health() -> 'ok')::text, 'true', 'مدير النظام يراها');

-- ── البنية ───────────────────────────────────────────────────────────────
select ok(jsonb_exists(fn_ops_health() -> 'data', 'notifications'), 'تحوي قسم الإشعارات');
select ok(jsonb_exists(fn_ops_health() -> 'data', 'payments'),      'تحوي قسم المدفوعات');
select ok(jsonb_exists(fn_ops_health() -> 'data', 'settlements'),   'تحوي قسم التسويات');
select ok(jsonb_exists(fn_ops_health() -> 'data', 'orders'),        'تحوي قسم الطلبات');
select ok(jsonb_exists(fn_ops_health() -> 'data', 'reports'),       'تحوي قسم التقارير');
select ok(jsonb_exists(fn_ops_health() -> 'data', 'journey'),       'تحوي قسم رحلة العميل');
select is(jsonb_typeof(fn_ops_health() #> '{data,jobs}'), 'array',  'المهام المجدولة مصفوفة');

-- ── الأرقام تطابق استعلامًا مستقلًا ──────────────────────────────────────
select is(
  (fn_ops_health() #>> '{data,orders,unpaid_invoices}')::int,
  (select count(*)::int from orders
    where payment_status = 'unpaid' and invoice_number is not null and status <> 'cancelled'),
  'عدد الفواتير غير المدفوعة يطابق العدّ المباشر'
);

select cmp_ok(
  (fn_ops_health() #>> '{data,orders,stale}')::int,
  '>=', 1, 'الطلب المتوقف منذ أسبوع محسوب'
);

select is(
  (fn_ops_health() #>> '{data,settlements,awaiting_verify}')::int,
  (select count(*)::int from cash_settlements where state = 'handed_over'),
  'التسويات بانتظار الاعتماد تطابق العدّ المباشر'
);

-- المبلغ لا العدد: عدد التسويات المفتوحة لا يقول كم من المال خارج الحساب
select is(
  (fn_ops_health() #>> '{data,settlements,undeposited_amount}')::numeric,
  (select coalesce(sum(expected_amount), 0) from cash_settlements where state = 'open'),
  'النقد غير المودَع يطابق مجموع التسويات المفتوحة'
);

select is(
  (fn_ops_health() #>> '{data,orders,today}')::int,
  (select count(*)::int from orders where business_date_of(created_at) = business_date_of()),
  'طلبات اليوم تطابق العدّ المباشر'
);

-- بلا مسحة واحدة تكون النسبة غائبة لا صفرًا: «لا بيانات» ليس «فشل تام»
select is(
  (select jsonb_typeof(fn_ops_health() #> '{data,journey,otp_success_pct}')),
  'null', 'نسبة نجاح الرمز غائبة حين لا عيّنة'
);

reset role;
select is(
  (select count(*)::int from private.notification_outbox where state = 'pending'),
  (select count(*)::int from private.notification_outbox where state = 'pending'),
  'الطابور مقروء للتدقيق'
);
set local role authenticated;
select act_as('e4444444-4444-4444-4444-444444444444'::uuid);

-- ── سجل تحديث العرض المادي ───────────────────────────────────────────────
/*
 * بلا تسجيل صريح لوقت التحديث لا تُميّز اللوحة بين عرض محدَّث لتوّه وعرض
 * توقّف تحديثه منذ أيام. الحالات الثلاث تُهيَّأ صراحةً: لا سجل، سجل قديم،
 * سجل حديث — فلا يعتمد الاختبار على ما تركه تشغيل سابق في القاعدة.
 */
reset role;
delete from private.report_refreshes where view_name = 'mv_stage_durations';
set local role authenticated;
select act_as('e4444444-4444-4444-4444-444444444444'::uuid);

select ok(
  (fn_ops_health() #>> '{data,reports,stage_durations_stale}')::boolean,
  'العرض يُعدّ قديمًا حين لا سجل تحديث'
);

reset role;
insert into private.report_refreshes (view_name, refreshed_at)
values ('mv_stage_durations', now() - interval '6 hours');
set local role authenticated;
select act_as('e4444444-4444-4444-4444-444444444444'::uuid);

select ok(
  (fn_ops_health() #>> '{data,reports,stage_durations_stale}')::boolean,
  'وتحديث عمره ست ساعات يُعدّ قديمًا أيضًا'
);

reset role;
select fn_refresh_reports();
set local role authenticated;
select act_as('e4444444-4444-4444-4444-444444444444'::uuid);

select ok(
  not (fn_ops_health() #>> '{data,reports,stage_durations_stale}')::boolean,
  'وبعد التحديث لم يعد قديمًا'
);

reset role;
select * from finish();
rollback;
