-- الفوترة والدفع: الحجز على مرحلتين، والـwebhook معاد الأمان، والصلاحيات.
begin;
select plan(40);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'operator@t.local'),
  ('a3333333-3333-3333-3333-333333333333', 'admin@t.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد المندوب', 'courier'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد المشغّل', 'operator'),
  ('b3333333-3333-3333-3333-333333333333', 'a3333333-3333-3333-3333-333333333333', 'سالم المدير', 'admin');

insert into properties (id, code, name)
values ('c1111111-1111-1111-1111-111111111111', 'TSTP', 'برج الدفع');

insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'أحمد', '+96891234500', '1', '1', 'complete', now());

insert into customer_qr_tokens (customer_id, token)
values ('d1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111');

insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by)
values ('f1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'ready', now(), 'b2222222-2222-2222-2222-222222222222'),
       ('f2222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'ready', now(), 'b2222222-2222-2222-2222-222222222222');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

-- ── الصلاحية ──────────────────────────────────────────────────────────────
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  fn_reserve_invoice('f1111111-1111-1111-1111-111111111111', 'INV-1', 5.000, 'k1') ->> 'code',
  'forbidden', 'المندوب لا ينشئ فاتورة'
);

select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

-- ── التحقق من المدخلات ────────────────────────────────────────────────────
select is(
  fn_reserve_invoice('f1111111-1111-1111-1111-111111111111', 'INV-1', 0.050, 'k1') ->> 'code',
  'invalid_input', 'قيمة تحت الحد الأدنى تُرفض'
);

select is(
  fn_reserve_invoice('f1111111-1111-1111-1111-111111111111', '', 5.000, 'k1') ->> 'code',
  'invalid_input', 'رقم فاتورة فارغ يُرفض'
);

-- ── الحجز ثم الربط ────────────────────────────────────────────────────────
create temp table reserved as
select (fn_reserve_invoice('f1111111-1111-1111-1111-111111111111', 'INV-1', 4.500, 'k1')
        #>> '{data,payment_id}')::uuid as payment_id;

select isnt((select payment_id from reserved), null, 'الحجز ينجح');

select is(
  (select amount_baisa from payments where id = (select payment_id from reserved)),
  4500::bigint, 'الريال يتحوّل إلى بيسة بلا خطأ عشري'
);

-- الحجز وحده لا يفوتر ولا ينقل الحالة
select is(
  (select status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'ready'::order_status, 'الحجز لا ينقل الحالة'
);

select is(
  (select invoice_number from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  null, 'ولا يكتب رقم الفاتورة'
);

-- رقم الفاتورة مقفل منذ الحجز، فلا تُنشأ جلسة دفع لرقم مكرر
select is(
  (fn_attach_checkout((select payment_id from reserved), 'INV-1', 4.500,
                      'sess_1', 'https://pay/1', 'rt-hash-1') ->> 'ok')::boolean,
  true, 'الربط ينجح'
);

select is(
  (select status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'out_for_delivery'::order_status, 'الربط ينقل الحالة إلى «خرج للتوصيل»'
);

select is(
  (select invoice_amount from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  4.500::numeric(12,3), 'والفاتورة محفوظة'
);

-- ── فشل المزود: تحرير الحجز لا يترك أثرًا ────────────────────────────────
create temp table reserved2 as
select (fn_reserve_invoice('f2222222-2222-2222-2222-222222222222', 'INV-2', 7.000, 'k2')
        #>> '{data,payment_id}')::uuid as payment_id;

select lives_ok(
  $$ select fn_release_invoice((select payment_id from reserved2), 'فشل ثواني') $$,
  'تحرير الحجز ينجح'
);

select is(
  (select status from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  'ready'::order_status, 'فشل المزود لا ينقل الحالة'
);

select is(
  (select invoice_number from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  null, 'ولا يترك فاتورة'
);

select is(
  (select count(*)::int from payments where order_id = 'f2222222-2222-2222-2222-222222222222'),
  0, 'ولا سجل دفع'
);

-- الرقم متاح مجددًا بعد التحرير
select is(
  (fn_reserve_invoice('f2222222-2222-2222-2222-222222222222', 'INV-2', 7.000, 'k3')
    ->> 'ok')::boolean,
  true, 'رقم الفاتورة متاح بعد التحرير'
);

-- ── رقم فاتورة مكرر ───────────────────────────────────────────────────────
select is(
  fn_reserve_invoice('f2222222-2222-2222-2222-222222222222', 'INV-1', 3.000, 'k4') ->> 'code',
  'duplicate_invoice', 'رقم فاتورة مكرر يُرفض'
);

-- ── الدفع النقدي ──────────────────────────────────────────────────────────
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  (fn_record_cash_payment('f1111111-1111-1111-1111-111111111111') ->> 'ok')::boolean,
  true, 'المندوب يسجّل الدفع النقدي'
);

select is(
  (select payment_status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'paid'::payment_status, 'الطلب يصبح مدفوعًا'
);

select is(
  (select paid_recorded_by from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'b1111111-1111-1111-1111-111111111111'::uuid, 'باسم من استلم المبلغ'
);

-- التحصيل يُقيَّد في تسوية يومه ويحدّث المتوقّع
select is(
  (select count(*)::int from cash_settlements
    where courier_id = 'b1111111-1111-1111-1111-111111111111'),
  1, 'تسوية اليوم تُفتح تلقائيًا'
);

select is(
  (select expected_amount from cash_settlements
    where courier_id = 'b1111111-1111-1111-1111-111111111111'),
  4.500::numeric(12,3), 'المتوقّع يساوي مبلغ الفاتورة'
);

select is(
  fn_record_cash_payment('f1111111-1111-1111-1111-111111111111') ->> 'code',
  'stale_state', 'لا تحصيل مرتين لطلب واحد'
);

-- ── التسليم بعد الدفع ─────────────────────────────────────────────────────
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  (fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'delivery',
    'e1111111-1111-1111-1111-111111111111', 'delivery/p.jpg', 4000, 'sha-p')
    ->> 'ok')::boolean,
  true, 'التسليم ينجح بعد تسجيل الدفع'
);

-- ── إلغاء الدفع ───────────────────────────────────────────────────────────
select is(
  fn_reverse_payment('f1111111-1111-1111-1111-111111111111', 'خطأ') ->> 'code',
  'forbidden', 'المشغّل لا يلغي دفعًا'
);

select act_as('a3333333-3333-3333-3333-333333333333'::uuid);

select is(
  fn_reverse_payment('f1111111-1111-1111-1111-111111111111', 'ab') ->> 'code',
  'invalid_input', 'الإلغاء يتطلب سببًا'
);

-- ── الـwebhook ────────────────────────────────────────────────────────────
set local role service_role;

select is(
  (fn_apply_payment_webhook('sess_unknown', 'paid') #>> '{data,reason}'),
  'unknown_session', 'جلسة غير معروفة لا تُطبَّق ولا تُفشل الرد'
);

create temp table sess2 as
select (fn_reserve_invoice('f2222222-2222-2222-2222-222222222222', 'INV-9', 6.000, 'k9')
        #>> '{data,payment_id}')::uuid as payment_id;

reset role;
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);
select fn_attach_checkout((select payment_id from sess2), 'INV-9', 6.000,
                          'sess_9', 'https://pay/9', 'rt-9');
set local role service_role;

select is(
  (fn_apply_payment_webhook('sess_9', 'cancelled') #>> '{data,reason}'),
  'not_paid', 'حالة غير مدفوعة لا تُطبَّق'
);

select is(
  (select payment_status from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  'unpaid'::payment_status, 'والطلب يبقى غير مدفوع'
);

select is(
  (fn_apply_payment_webhook('sess_9', 'paid') #>> '{data,applied}')::boolean,
  true, 'الدفع المؤكد يُطبَّق'
);

select is(
  (select payment_status from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  'paid'::payment_status, 'الطلب يصبح مدفوعًا'
);

select is(
  (select payment_method from orders where id = 'f2222222-2222-2222-2222-222222222222'),
  'thawani'::payment_method, 'بطريقة ثواني'
);

-- إعادة الإرسال بلا أثر ثانٍ
select is(
  (fn_apply_payment_webhook('sess_9', 'paid') #>> '{data,reason}'),
  'already_paid', 'webhook مكرر بلا أثر ثانٍ'
);

-- كل استدعاء يُسجَّل حتى لو لم يغيّر شيئًا
select cmp_ok(
  (select count(*)::int from payment_events
    where order_id = 'f2222222-2222-2222-2222-222222222222' and event_type = 'webhook'),
  '>=', 3, 'كل استدعاء webhook مسجّل'
);

-- ── لا إلغاء يدوي لدفع أكدته ثواني ───────────────────────────────────────
reset role;
select act_as('a3333333-3333-3333-3333-333333333333'::uuid);

select is(
  fn_reverse_payment('f2222222-2222-2222-2222-222222222222', 'محاولة إلغاء') ->> 'code',
  'forbidden', 'دفع ثواني المؤكد لا يُلغى يدويًا'
);

-- ── المصالحة ──────────────────────────────────────────────────────────────
set local role service_role;

select is(
  (select count(*)::int from fn_payments_awaiting_reconciliation(0)),
  0, 'لا دفعات معلّقة بعد تأكيدها'
);

insert into orders (id, customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                    invoice_number, invoice_amount, invoiced_at)
values ('f3333333-3333-3333-3333-333333333333', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'out_for_delivery', now(),
        'b2222222-2222-2222-2222-222222222222', 'INV-7', 3.000, now());

insert into payments (order_id, amount_baisa, status, provider_session_id, idempotency_key, created_at)
values ('f3333333-3333-3333-3333-333333333333', 3000, 'pending', 'sess_stale', 'k-stale',
        now() - interval '30 minutes');

select is(
  (select count(*)::int from fn_payments_awaiting_reconciliation(10)),
  1, 'المصالحة تلتقط دفعة فات webhookها'
);

select is(
  (select session_id from fn_payments_awaiting_reconciliation(10)),
  'sess_stale', 'وتعيد معرّف جلستها'
);

-- ── الاحتفاظ بالبيانات ────────────────────────────────────────────────────
select is(
  (fn_apply_retention() ->> 'ok')::boolean,
  true, 'التنظيف وفق سياسة الاحتفاظ يعمل'
);

-- المسحات المرتبطة بطلب تبقى مع طلبها مهما مضى عليها
insert into scan_events (id, customer_id, scan_session_id, result, scanned_at)
values ('aa111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
        gen_random_uuid(), 'order_submitted', now() - interval '400 days');

update orders set scan_event_id = 'aa111111-1111-1111-1111-111111111111'
 where id = 'f3333333-3333-3333-3333-333333333333';

select fn_apply_retention();

select is(
  (select count(*)::int from scan_events where id = 'aa111111-1111-1111-1111-111111111111'),
  1, 'المسحة المرتبطة بطلب لا تُحذف'
);

insert into scan_events (id, customer_id, scan_session_id, result, scanned_at)
values ('aa222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111',
        gen_random_uuid(), 'abandoned', now() - interval '400 days');

select fn_apply_retention();

select is(
  (select count(*)::int from scan_events where id = 'aa222222-2222-2222-2222-222222222222'),
  0, 'المسحة المتروكة القديمة تُحذف'
);

select * from finish();
rollback;
