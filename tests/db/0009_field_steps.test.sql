-- العمليات الميدانية: الذرّية والمطابقة وبوابة الدفع.
begin;
select plan(31);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'op@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'op2@t.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'سالم الموظف', 'operator'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد الموظف', 'operator');

insert into properties (id, code, name)
values ('c1111111-1111-1111-1111-111111111111', 'TSTF', 'برج الميدان');

insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'أحمد', '+96891234567', '3', '12', 'complete', now()),
       ('d2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111',
        'سعيد', '+96891234568', '4', '5', 'complete', now());

insert into customer_qr_tokens (customer_id, token) values
  ('d1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111'),
  ('d2222222-2222-2222-2222-222222222222', 'e2222222-2222-2222-2222-222222222222');

insert into orders (id, customer_id, property_id) values
  ('f1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
   'c1111111-1111-1111-1111-111111111111');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

-- ── الانتقال اليدوي ───────────────────────────────────────────────────────
select is(
  fn_advance_status('f1111111-1111-1111-1111-111111111111', 'confirmed', 'picked_up') ->> 'code',
  'stale_state', 'حالة متوقَّعة خاطئة تُرفض قبل أي تغيير'
);

select is(
  (fn_advance_status('f1111111-1111-1111-1111-111111111111', 'new', 'confirmed')
    ->> 'ok')::boolean,
  true, 'الانتقال المسموح ينجح'
);

-- الانتقالات الميدانية لا تحدث بضغطة زر
select is(
  fn_advance_status('f1111111-1111-1111-1111-111111111111', 'confirmed', 'picked_up') ->> 'code',
  'invalid_transition', 'الاستلام لا يتم بزر الحالة'
);

-- ── تعارض موظفَين ─────────────────────────────────────────────────────────
select is(
  fn_advance_status('f1111111-1111-1111-1111-111111111111', 'new', 'confirmed') ->> 'code',
  'stale_state', 'الموظف الثاني يحصل على stale_state لا تقدّمًا إضافيًا'
);

select is(
  fn_advance_status('f1111111-1111-1111-1111-111111111111', 'new', 'confirmed')
    #>> '{data,actual_status}',
  'confirmed', 'الرد يحمل الحالة الفعلية لتعيد الواجهة التحميل'
);

-- ── الاستلام الميداني ─────────────────────────────────────────────────────
-- رمز عميل آخر يُرفض ولو كان صالحًا بذاته
select is(
  fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'pickup',
    'e2222222-2222-2222-2222-222222222222', 'pickup/a.jpg', 5000, 'sha-a') ->> 'code',
  'qr_mismatch', 'رمز عميل آخر يُرفض'
);

select is(
  (select status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'confirmed'::order_status,
  'الحالة لا تتغير عند عدم المطابقة'
);

select is(
  (select count(*)::int from order_photos where order_id = 'f1111111-1111-1111-1111-111111111111'),
  0, 'ولا تُحفظ صورة'
);

select is(
  fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'pickup',
    '00000000-0000-0000-0000-000000000000', 'pickup/a.jpg', 5000, 'sha-a') ->> 'code',
  'qr_mismatch', 'رمز غير موجود يُرفض'
);

select is(
  (fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'pickup',
    'e1111111-1111-1111-1111-111111111111', 'pickup/a.jpg', 5000, 'sha-a')
    ->> 'ok')::boolean,
  true, 'الاستلام ينجح بالرمز الصحيح والصورة'
);

-- السجل المُعاد هو المحفوظ فعلًا لا حالة متوقَّعة
select is(
  fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'pickup',
    'e1111111-1111-1111-1111-111111111111', 'pickup/b.jpg', 5000, 'sha-b')
    ->> 'code',
  'stale_state', 'تكرار الاستلام يُرفض'
);

select is(
  (select status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'picked_up'::order_status,
  'الحالة محفوظة فعلًا'
);

select is(
  (select pickup_confirmed_by from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'b1111111-1111-1111-1111-111111111111'::uuid,
  'الموظف المنفّذ مسجّل'
);

select is(
  (select kind from order_photos where order_id = 'f1111111-1111-1111-1111-111111111111'),
  'pickup'::photo_kind,
  'صورة الاستلام محفوظة'
);

-- ── الذرّية: فشل في منتصف العملية لا يترك أثرًا ──────────────────────────
insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at,
                    payment_status, payment_method, paid_at, paid_recorded_by)
values ('f2222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b1111111-1111-1111-1111-111111111111', 'INV-T1', 5.000, now(),
        'paid', 'cash_on_delivery', now(), 'b1111111-1111-1111-1111-111111111111');

-- بصمة مستخدمة سابقًا: يفشل إدراج الصورة بعد اجتياز كل الفحوص
select is(
  fn_confirm_field_step('f2222222-2222-2222-2222-222222222222', 'delivery',
    'e1111111-1111-1111-1111-111111111111', 'delivery/x.jpg', 5000, 'sha-a') ->> 'code',
  'photo_rejected', 'بصمة صورة مكررة تُرفض'
);

select is(
  (select status from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  'out_for_delivery'::order_status,
  'الفشل في منتصف العملية لا يغيّر الحالة'
);

select is(
  (select delivery_confirmed_at from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  null, 'ولا يسجّل وقت تأكيد'
);

select is(
  (select count(*)::int from order_photos
    where order_id = 'f2222222-2222-2222-2222-222222222222'),
  0, 'ولا يترك صورة'
);

-- ── بوابة الدفع ───────────────────────────────────────────────────────────
insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f3333333-3333-3333-3333-333333333333', 'd2222222-2222-2222-2222-222222222222',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b1111111-1111-1111-1111-111111111111', 'INV-T2', 7.000, now());

select is(
  fn_confirm_field_step('f3333333-3333-3333-3333-333333333333', 'delivery',
    'e2222222-2222-2222-2222-222222222222', 'delivery/y.jpg', 5000, 'sha-y') ->> 'code',
  'payment_required', 'لا تسليم قبل الدفع'
);

select is(
  (select status from orders where id = 'f3333333-3333-3333-3333-333333333333'),
  'out_for_delivery'::order_status,
  'الطلب غير المدفوع يبقى كما هو'
);

update orders set payment_status = 'paid', payment_method = 'cash_on_delivery',
       paid_at = now(), paid_recorded_by = 'b1111111-1111-1111-1111-111111111111'
 where id = 'f3333333-3333-3333-3333-333333333333';

select is(
  (fn_confirm_field_step('f3333333-3333-3333-3333-333333333333', 'delivery',
    'e2222222-2222-2222-2222-222222222222', 'delivery/y.jpg', 5000, 'sha-y')
    ->> 'ok')::boolean,
  true, 'التسليم ينجح بعد تسجيل الدفع'
);

select is(
  (select status from orders where id = 'f3333333-3333-3333-3333-333333333333'),
  'completed'::order_status,
  'الطلب يصل إلى «مكتمل»'
);

-- ── الحالة النهائية مقفلة ────────────────────────────────────────────────
select is(
  fn_cancel_order('f3333333-3333-3333-3333-333333333333', 'محاولة إلغاء') ->> 'code',
  'invalid_transition', 'لا إلغاء بعد الاكتمال'
);

select is(
  fn_advance_status('f3333333-3333-3333-3333-333333333333', 'completed', 'ready') ->> 'code',
  'invalid_transition', 'لا رجوع من الحالة النهائية'
);

-- ── الإلغاء ───────────────────────────────────────────────────────────────
select is(
  fn_cancel_order('f1111111-1111-1111-1111-111111111111', 'ab') ->> 'code',
  'invalid_input', 'الإلغاء يتطلب سببًا'
);

select is(
  (fn_cancel_order('f1111111-1111-1111-1111-111111111111', 'العميل ألغى الطلب')
    ->> 'ok')::boolean,
  true, 'الإلغاء ينجح مع سبب'
);

select is(
  (select cancel_reason from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'العميل ألغى الطلب',
  'السبب محفوظ'
);

-- ── سجل الحالات يوثّق كل انتقال ──────────────────────────────────────────
select cmp_ok(
  (select count(*)::int from order_status_history
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  '>=', 4,
  'كل انتقال مسجّل: إنشاء ← مؤكد ← تم الاستلام ← ملغي'
);

select is(
  (select changed_by from order_status_history
    where order_id = 'f1111111-1111-1111-1111-111111111111'
      and to_status = 'picked_up'),
  'b1111111-1111-1111-1111-111111111111'::uuid,
  'السجل يحفظ منفّذ كل انتقال'
);

-- ── الصلاحية ──────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '', true);

select is(
  fn_confirm_field_step('f2222222-2222-2222-2222-222222222222', 'delivery',
    'e1111111-1111-1111-1111-111111111111', 'd/z.jpg', 5000, 'sha-z') ->> 'code',
  'forbidden', 'بلا جلسة موظف لا تنفيذ'
);

select is(
  fn_advance_status('f2222222-2222-2222-2222-222222222222', 'out_for_delivery', 'cancelled')
    ->> 'code',
  'forbidden', 'ولا انتقال'
);

select * from finish();
rollback;
