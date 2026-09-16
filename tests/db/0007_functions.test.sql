-- دوال المرحلة الأولى: الصلاحية مفحوصة داخل الدالة لا في الواجهة.
begin;
select plan(21);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'manager@t.local'),
  ('a3333333-3333-3333-3333-333333333333', 'admin@t.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد المندوب', 'courier'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد المشرف', 'manager'),
  ('b3333333-3333-3333-3333-333333333333', 'a3333333-3333-3333-3333-333333333333', 'سالم المدير', 'admin');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

-- العميل المنشأ داخل هذا الاختبار وحده، لا «أول عميل في الجدول»:
-- الاعتماد على قاعدة فارغة يجعل الاختبار يكسر مع أي بيانات بذرية.
create or replace function test_customer_id() returns uuid language sql as
  $f$ select c.id from customers c
        join properties p on p.id = c.property_id
       where p.code like 'TST%' order by c.customer_no desc limit 1 $f$;

-- ── العقارات: manager فأعلى ───────────────────────────────────────────────
select act_as('b1111111-1111-1111-1111-111111111111'::uuid); -- المندوب
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  fn_upsert_property(null, 'BRJ1', 'برج النهضة') ->> 'code',
  'forbidden',
  'المندوب لا ينشئ عقارًا'
);

select act_as('a2222222-2222-2222-2222-222222222222'::uuid); -- المشرف

select is(
  (fn_upsert_property(null, 'TST1', 'برج الاختبار') ->> 'ok')::boolean,
  true,
  'المشرف ينشئ عقارًا'
);

select is(
  fn_upsert_property(null, 'TST1', 'مكرر') ->> 'code',
  'invalid_input',
  'رمز عقار مكرر يُرفض برمز خطأ لا باستثناء'
);

select is(
  (fn_upsert_property(null, 'TST2', 'برج ثانٍ', 'مسقط', 23.588, 58.3829) ->> 'ok')::boolean,
  true,
  'العقار بالإحداثيات يُقبل'
);

-- ── حذف العقار: admin فقط، ولا يترك عملاء بلا عقار ───────────────────────
select is(
  fn_delete_property((select id from properties where code = 'TST2')) ->> 'code',
  'forbidden',
  'المشرف لا يحذف عقارًا'
);

-- ── إنشاء العميل ورمزه ────────────────────────────────────────────────────
select act_as('a1111111-1111-1111-1111-111111111111'::uuid); -- المندوب

select is(
  (fn_create_customer_with_qr((select id from properties where code = 'TST1')) ->> 'ok')::boolean,
  true,
  'المندوب ينشئ عميلًا ورمزًا'
);

select is(
  (select count(*)::int from customer_qr_tokens t
    where t.customer_id = test_customer_id() and t.revoked_at is null),
  1,
  'العميل الجديد له رمز فعّال واحد'
);

select is(
  (select profile_status from customers where id = test_customer_id()),
  'incomplete'::profile_status,
  'العميل الجديد بحالة «غير مكتمل»'
);

-- العقار المعطَّل لا يُقبل ولو كان المفتاح الأجنبي صالحًا
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);
select fn_set_property_active((select id from properties where code = 'TST2'), false);
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select is(
  fn_create_customer_with_qr((select id from properties where code = 'TST2')) ->> 'code',
  'inactive_property',
  'لا عميل على عقار معطَّل'
);

select is(
  fn_create_customer_with_qr('00000000-0000-0000-0000-000000000000') ->> 'code',
  'inactive_property',
  'لا عميل على عقار غير موجود'
);

-- ── إعادة إصدار الرمز ─────────────────────────────────────────────────────
select is(
  fn_reissue_qr(test_customer_id(), 'ab') ->> 'code',
  'invalid_input',
  'إعادة الإصدار تتطلب سببًا'
);

select is(
  (fn_reissue_qr(test_customer_id(), 'فقدان الملصق') ->> 'ok')::boolean,
  true,
  'إعادة الإصدار تنجح مع سبب'
);

select is(
  (select count(*)::int from customer_qr_tokens
    where customer_id = test_customer_id() and revoked_at is null),
  1,
  'رمز فعّال واحد بعد إعادة الإصدار'
);

-- تاريخ الرمز محفوظ: نعرف أنه كان صحيحًا يومًا، فنردّ برسالة صحيحة لا «غير صالح»
select is(
  (select count(*)::int from customer_qr_tokens
    where customer_id = test_customer_id() and revoked_at is not null),
  1,
  'الرمز السابق محفوظ مُبطلًا لا محذوفًا'
);

select is(
  (select revoke_reason from customer_qr_tokens
    where customer_id = test_customer_id() and revoked_at is not null),
  'فقدان الملصق',
  'سبب الإبطال محفوظ'
);

-- ── نقل العميل بين العقارات ───────────────────────────────────────────────
select is(
  fn_move_customer_property(test_customer_id(),
                            (select id from properties where code = 'TST1'),
                            'انتقل') ->> 'code',
  'forbidden',
  'المندوب لا ينقل عميلًا بين العقارات'
);

-- ── التدقيق يُكتب تلقائيًا ────────────────────────────────────────────────
select cmp_ok(
  (select count(*)::int from private.audit_logs where entity = 'customer_qr_tokens'),
  '>=', 2,
  'إصدار الرمز وإبطاله مسجّلان في التدقيق'
);

-- ── صلاحية التنفيذ نفسها ──────────────────────────────────────────────────
-- الدوال تُستدعى بجلسة الموظف؛ anon لا ينفّذ أيًّا منها.
set local role anon;

select throws_ok(
  $$ select fn_create_customer_with_qr('00000000-0000-0000-0000-000000000000') $$,
  '42501', null, 'anon لا ينفّذ دالة إنشاء العميل'
);

select throws_ok(
  $$ select fn_upsert_property(null, 'X9', 'محاولة') $$,
  '42501', null, 'anon لا ينفّذ دالة العقارات'
);

reset role;

-- الموظف ينفّذ الدالة فعليًا بدور authenticated، لا بصلاحيات المالك
set local role authenticated;
select act_as('a2222222-2222-2222-2222-222222222222'::uuid);

select is(
  (fn_upsert_property(null, 'TST9', 'برج تاسع') ->> 'ok')::boolean,
  true,
  'المشرف ينفّذ الدالة بجلسته هو'
);

-- الكتابة المباشرة تبقى ممنوعة رغم أن الدالة تكتب — الطبقتان مستقلتان
select throws_ok(
  $$ insert into properties (code, name) values ('TSTX', 'مباشر') $$,
  '42501', null, 'الكتابة المباشرة تبقى ممنوعة رغم نجاح الدالة'
);

reset role;

select * from finish();
rollback;
