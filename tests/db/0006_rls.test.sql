-- سياسات RLS: الواجهة تقرأ ولا تكتب، وanon لا يصل إلى شيء.
begin;
select plan(23);

insert into properties (id, code, name)
values ('11111111-1111-1111-1111-111111111111', 'TSTA', 'برج الاختبار أ');
insert into customers (id, property_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'operator@t.local'),
  ('a3333333-3333-3333-3333-333333333333', 'disabled@t.local');
insert into staff (id, user_id, full_name, role, is_active) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد المندوب', 'courier', true),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد المشغّل', 'operator', true),
  ('b3333333-3333-3333-3333-333333333333', 'a3333333-3333-3333-3333-333333333333', 'سعيد المعطَّل', 'operator', false);

insert into cash_settlements (courier_id, business_date)
values ('b1111111-1111-1111-1111-111111111111', '2026-09-16'),
       ('b2222222-2222-2222-2222-222222222222', '2026-09-16');

-- ── anon لا يصل إلى شيء ───────────────────────────────────────────────────
set local role anon;

select throws_ok($$ select * from properties $$,  '42501', null, 'anon لا يقرأ العقارات');
select throws_ok($$ select * from customers  $$,  '42501', null, 'anon لا يقرأ العملاء');
select throws_ok($$ select * from orders     $$,  '42501', null, 'anon لا يقرأ الطلبات');
select throws_ok($$ select * from staff      $$,  '42501', null, 'anon لا يقرأ الموظفين');
select throws_ok($$ select * from customer_qr_tokens $$, '42501', null, 'anon لا يقرأ رموز QR');
select throws_ok($$ select * from private.audit_logs $$, '42501', null, 'anon لا يصل إلى private');

reset role;

-- ── الموظف الفعّال يقرأ ────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1111111-1111-1111-1111-111111111111')::text, true);

select isnt_empty($$ select id from properties $$, 'الموظف يقرأ العقارات');
select isnt_empty($$ select id from customers  $$, 'الموظف يقرأ العملاء');
select is((select auth_role()), 'courier'::staff_role, 'الدور يُقرأ من الجلسة');

-- ── الواجهة لا تكتب على أي جدول ───────────────────────────────────────────
select throws_ok(
  $$ insert into properties (code, name) values ('NEW1', 'محاولة') $$,
  '42501', null, 'الموظف لا يضيف عقارًا مباشرة'
);

select throws_ok(
  $$ update properties set name = 'تعديل' where code = 'TSTA' $$,
  '42501', null, 'الموظف لا يعدّل عقارًا مباشرة'
);

select throws_ok(
  $$ insert into customers (property_id) values ('11111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'الموظف لا ينشئ عميلًا مباشرة'
);

select throws_ok(
  $$ update orders set status = 'confirmed' $$,
  '42501', null, 'الموظف لا يغيّر حالة طلب مباشرة'
);

select throws_ok(
  $$ delete from customers where id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null, 'الموظف لا يحذف عميلًا مباشرة'
);

-- ── جداول لا يقرأها أحد ───────────────────────────────────────────────────
select throws_ok($$ select * from otp_challenges $$,
  '42501', null, 'حتى الموظف لا يقرأ تحديات OTP');
select throws_ok($$ select * from order_submissions $$,
  '42501', null, 'حتى الموظف لا يقرأ رموز الإرسال');
select throws_ok($$ select * from private.audit_logs $$,
  '42501', null, 'الموظف لا يصل إلى مخطط private');

-- ── المندوب يرى تسوياته وحدها ─────────────────────────────────────────────
select is(
  (select count(*)::int from cash_settlements),
  1,
  'المندوب يرى تسويته فقط'
);

-- ── المشغّل يرى تسويات الجميع ──────────────────────────────────────────────
select set_config('request.jwt.claims',
  json_build_object('sub', 'a2222222-2222-2222-2222-222222222222')::text, true);

select is(
  (select count(*)::int from cash_settlements),
  2,
  'المشغّل يرى تسويات الجميع'
);

select is((select auth_role()), 'operator'::staff_role, 'دور المشغّل صحيح');

-- ── الموظف المعطَّل يُرفض فورًا بلا انتظار انتهاء جلسته ───────────────────
select set_config('request.jwt.claims',
  json_build_object('sub', 'a3333333-3333-3333-3333-333333333333')::text, true);

select is((select auth_role()), null, 'الموظف المعطَّل بلا دور');
select is_empty($$ select id from properties $$, 'الموظف المعطَّل لا يقرأ شيئًا');
select is_empty($$ select id from orders $$, 'الموظف المعطَّل لا يرى الطلبات');

reset role;
select * from finish();
rollback;
