-- دورة التسوية: الإيداع الموثَّق، الاعتماد عن بُعد، والمطابقة البنكية.
begin;
select plan(41);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'operator@t.local'),
  ('a3333333-3333-3333-3333-333333333333', 'manager@t.local'),
  ('a4444444-4444-4444-4444-444444444444', 'admin@t.local');
insert into staff (id, user_id, full_name, role, phone) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد المندوب', 'courier', '+96891110001'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد المشغّل', 'operator', '+96891110002'),
  ('b3333333-3333-3333-3333-333333333333', 'a3333333-3333-3333-3333-333333333333', 'سعيد المشرف', 'manager', '+96891110003'),
  ('b4444444-4444-4444-4444-444444444444', 'a4444444-4444-4444-4444-444444444444', 'سالم المدير', 'admin', '+96891110004');

insert into properties (id, code, name)
values ('c1111111-1111-1111-1111-111111111111', 'TSTS', 'برج التسوية');
insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'أحمد', '+96891234599', '2', '7', 'complete', now());

insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b2222222-2222-2222-2222-222222222222', 'INV-S1', 10.000, now()),
       ('f2222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b2222222-2222-2222-2222-222222222222', 'INV-S2', 5.000, now());

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

-- ── التحصيل يفتح التسوية ─────────────────────────────────────────────────
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);
select fn_record_cash_payment('f1111111-1111-1111-1111-111111111111');
select fn_record_cash_payment('f2222222-2222-2222-2222-222222222222');

create temp table s1 as
select id from cash_settlements where courier_id = 'b1111111-1111-1111-1111-111111111111';

select is(
  (select expected_amount from cash_settlements where id = (select id from s1)),
  15.000::numeric(12,3), 'المتوقّع مجموع التحصيلين'
);

-- ── الإيداع الموثَّق ──────────────────────────────────────────────────────
-- الطريقة تُحسم افتراضيًا إلى الإيداع البنكي
select is(
  fn_hand_over_settlement((select id from s1), 15.000) ->> 'code',
  'proof_required', 'الإيداع البنكي بلا صورة ولا رقم إيصال يُرفض'
);

select is(
  fn_hand_over_settlement((select id from s1), 15.000, 'bank_deposit', 'DEP-1') ->> 'code',
  'proof_required', 'الرقم وحده لا يكفي'
);

select is(
  fn_hand_over_settlement((select id from s1), 15.000, 'safe_drop', null, null, null, null) ->> 'code',
  'exception_reason_required', 'طريقة استثنائية بلا سبب تُرفض'
);

select is(
  (fn_hand_over_settlement((select id from s1), 15.000, 'bank_deposit', 'DEP-1',
                           'cash/1.jpg', 40000, 'sha-dep-1') ->> 'ok')::boolean,
  true, 'الإيداع البنكي بإثبات ورقم ينجح'
);

select is(
  (select state from cash_settlements where id = (select id from s1)),
  'handed_over'::settlement_state, 'الحالة تصبح «مُسلَّمة»'
);

select is(
  (select kind from order_photos where sha256 = 'sha-dep-1'),
  'cash_handover'::photo_kind, 'الإيصال محفوظ كصورة تسوية'
);

-- إيصال التسوية لا يخص طلبًا
select is(
  (select order_id from order_photos where sha256 = 'sha-dep-1'),
  null, 'إيصال الإيداع بلا طلب مرتبط'
);

-- ── التسوية المُسلَّمة لا تقبل تحصيلات ولا إلغاءً ─────────────────────────
select is(
  fn_hand_over_settlement((select id from s1), 15.000, 'bank_deposit', 'DEP-2',
                          'cash/2.jpg', 40000, 'sha-dep-2') ->> 'code',
  'settlement_locked', 'لا تسليم مرتين'
);

select is(
  fn_reverse_cash_collection(
    (select id from cash_collections where order_id = 'f2222222-2222-2222-2222-222222222222'),
    'خطأ في المبلغ') ->> 'code',
  'settlement_locked', 'لا إلغاء تحصيل بعد التسليم'
);

-- ── إعادة استخدام الإيصال ────────────────────────────────────────────────
insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f3333333-3333-3333-3333-333333333333', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b2222222-2222-2222-2222-222222222222', 'INV-S3', 8.000, now());

-- تحصيل بعد إيداع اليوم: يفتح تسوية يوم تالٍ بدل أن يُرفض
select is(
  (fn_record_cash_payment('f3333333-3333-3333-3333-333333333333') ->> 'ok')::boolean,
  true, 'التحصيل بعد إيداع اليوم يفتح تسوية يوم تالٍ'
);

create temp table s2 as
select id from cash_settlements
 where courier_id = 'b1111111-1111-1111-1111-111111111111'
   and business_date > business_date_of();

select is(
  (select expected_amount from cash_settlements where id = (select id from s2)),
  8.000::numeric(12,3), 'والتحصيل يُقيَّد في التسوية الجديدة'
);

select is(
  fn_hand_over_settlement((select id from s2), 8.000, 'bank_deposit',
                          'DEP-9', 'cash/9.jpg', 40000, 'sha-dep-1') ->> 'code',
  'proof_reused', 'إعادة استخدام إيصال سابق مرفوضة ببصمته'
);

-- ── لا يعتمد أحد تسويته هو — لكل دور ─────────────────────────────────────
select is(
  fn_verify_settlement((select id from s1), 15.000) ->> 'code',
  'forbidden', 'المندوب لا يعتمد أصلًا'
);

-- نمنح المندوب كل دور بدوره ونتحقق أن القاعدة لا تسقط مع أي منها
update staff set role = 'operator' where id = 'b1111111-1111-1111-1111-111111111111';
select is(
  fn_verify_settlement((select id from s1), 15.000) ->> 'code',
  'self_verification', 'operator لا يعتمد تسويته هو'
);

update staff set role = 'manager' where id = 'b1111111-1111-1111-1111-111111111111';
select is(
  fn_verify_settlement((select id from s1), 15.000) ->> 'code',
  'self_verification', 'manager لا يعتمد تسويته هو'
);

update staff set role = 'admin' where id = 'b1111111-1111-1111-1111-111111111111';
select is(
  fn_verify_settlement((select id from s1), 15.000) ->> 'code',
  'self_verification', 'admin لا يعتمد تسويته هو — لا استثناء لأي دور'
);

update staff set role = 'courier' where id = 'b1111111-1111-1111-1111-111111111111';

-- ── الاعتماد ──────────────────────────────────────────────────────────────
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  fn_verify_settlement((select id from s1), 14.500) ->> 'code',
  'invalid_input', 'فرق غير صفري بلا سبب يُرفض'
);

select is(
  (fn_verify_settlement((select id from s1), 14.950, 'عجز 0.050 — فكّة ناقصة')
    ->> 'ok')::boolean,
  true, 'الاعتماد بفرق ضمن السماح ينجح'
);

select is(
  (select state from cash_settlements where id = (select id from s1)),
  'verified'::settlement_state, 'الحالة تصبح معتمدة'
);

select is(
  (select variance from cash_settlements where id = (select id from s1)),
  -0.050::numeric(12,3), 'الفرق محسوب آليًا'
);

select is(
  (select verified_by from cash_settlements where id = (select id from s1)),
  'b2222222-2222-2222-2222-222222222222'::uuid, 'المدقّق مسجّل'
);

-- ── القفل بعد الاعتماد ───────────────────────────────────────────────────
select is(
  fn_verify_settlement((select id from s1), 15.000, 'إعادة') ->> 'code',
  'settlement_locked', 'التسوية المعتمدة مقفلة'
);

-- ── فرق خارج السماح ← متنازع عليها ───────────────────────────────────────
select fn_hand_over_settlement((select id from s2), 8.000, 'bank_deposit',
                               'DEP-9', 'cash/9.jpg', 40000, 'sha-dep-9')
  from (select act_as('a1111111-1111-1111-1111-111111111111'::uuid)) _;

select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  (fn_verify_settlement((select id from s2), 4.500, 'عجز كبير')
    ->> 'ok')::boolean,
  true, 'الاعتماد بفرق كبير يُقبل لكن لا يُعتمد'
);

select is(
  (select state from cash_settlements where id = (select id from s2)),
  'disputed'::settlement_state, 'يصبح متنازعًا عليه'
);

select is(
  fn_approve_variance((select id from s2), 'عُدّ بحضور المشرف') ->> 'code',
  'forbidden', 'المشغّل لا يعتمد فرقًا كبيرًا'
);

select act_as('a3333333-3333-3333-3333-333333333333'::uuid);

select is(
  (fn_approve_variance((select id from s2), 'عُدّ بحضور المشرف')
    ->> 'ok')::boolean,
  true, 'المشرف يعتمد الفرق الكبير'
);

select is(
  (select state from cash_settlements where id = (select id from s2)),
  'verified'::settlement_state, 'ويصبح معتمدًا'
);

-- ── المطابقة البنكية: الاستثناء الوحيد بعد الاعتماد ──────────────────────
select is(
  (fn_match_bank_deposit((select id from s1), 'TXN-2026-001') ->> 'ok')::boolean,
  true, 'المطابقة البنكية مسموحة بعد الاعتماد'
);

select is(
  (select bank_reference from cash_settlements where id = (select id from s1)),
  'TXN-2026-001', 'المرجع البنكي محفوظ'
);

-- ── التقارير ──────────────────────────────────────────────────────────────
set local role authenticated;
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  (select count(*)::int from v_unmatched_deposits),
  1, 'التسوية الثانية تظهر في المطابقة المعلّقة'
);

select is(
  (select count(*)::int from v_awaiting_verification),
  0, 'لا تسويات بانتظار الاعتماد'
);

select cmp_ok(
  (select verified_count from v_courier_variance_history
    where courier_id = 'b1111111-1111-1111-1111-111111111111'),
  '>=', 2, 'تاريخ الفروق يحسب التسويات المعتمدة'
);

select is(
  (select collections_count from v_daily_cash_reconciliation
    where business_date = business_date_of()),
  2, 'المطابقة اليومية تحسب التحصيلات'
);

-- المندوب يرى تسوياته وحدها — بلا فحص دور مكرر في كل تقرير
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  (select count(*)::int from v_courier_variance_history),
  1, 'المندوب يرى سجله هو فقط'
);

reset role;

-- ── المطابقة اليومية تساوي الطلبات المدفوعة نقدًا ────────────────────────
select is(
  (select sum(c.amount) from cash_collections c where c.reversed_at is null),
  (select sum(o.invoice_amount) from orders o
    where o.payment_method = 'cash_on_delivery' and o.payment_status = 'paid'),
  'مجموع التحصيلات = مجموع الطلبات المدفوعة نقدًا'
);

-- ── تذكير الإيداع ─────────────────────────────────────────────────────────
set local role service_role;

insert into cash_settlements (id, courier_id, business_date, expected_amount)
values ('ea111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111',
        business_date_of() - 5, 3.000);

select is(
  (fn_enqueue_handover_reminders() #>> '{data,queued}')::int,
  1, 'التذكير يُدرَج للتسوية المفتوحة'
);

select is(
  (fn_enqueue_handover_reminders() #>> '{data,queued}')::int,
  0, 'ولا يتكرر — مفتاح معاد الأمان'
);

select is(
  (select template_name from private.notification_outbox where kind = 'handover_reminder'),
  'ar_template', 'يستخدم القالب المعتمد بمتغير واحد'
);

-- ── الحجب بأيام العمل ────────────────────────────────────────────────────
reset role;
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f4444444-4444-4444-4444-444444444444', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b2222222-2222-2222-2222-222222222222', 'INV-S4', 2.000, now());

select is(
  fn_record_cash_payment('f4444444-4444-4444-4444-444444444444') ->> 'code',
  'unhanded_cash', 'نقد غير مودَع قديم يحجب التحصيل'
);

-- التسليم يرفع الحجب فورًا، بلا انتظار اعتماد المدقّق
select fn_hand_over_settlement('ea111111-1111-1111-1111-111111111111', 3.000, 'bank_deposit',
                               'DEP-OLD', 'cash/old.jpg', 40000, 'sha-old');

select is(
  (fn_record_cash_payment('f4444444-4444-4444-4444-444444444444') ->> 'ok')::boolean,
  true, 'التسليم وحده يرفع الحجب — لا ينتظر الاعتماد'
);

select * from finish();
rollback;
