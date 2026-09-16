-- بوابة الجاهزية وسجل الترحيل: الحارس والأرقام.
begin;
select plan(14);

insert into auth.users (id, email) values
  ('c1111111-1111-1111-1111-111111111111', 'launch-courier@t.local'),
  ('c2222222-2222-2222-2222-222222222222', 'launch-manager@t.local'),
  ('c3333333-3333-3333-3333-333333333333', 'launch-admin@t.local');
insert into staff (id, user_id, full_name, role) values
  ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 'مندوب', 'courier'),
  ('d2222222-2222-2222-2222-222222222222', 'c2222222-2222-2222-2222-222222222222', 'مشرف', 'manager'),
  ('d3333333-3333-3333-3333-333333333333', 'c3333333-3333-3333-3333-333333333333', 'مدير', 'admin');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

set local role authenticated;

-- ── بوابة الجاهزية ───────────────────────────────────────────────────────
select act_as('c1111111-1111-1111-1111-111111111111'::uuid);
select is(fn_launch_readiness() ->> 'code', 'forbidden', 'المندوب لا يرى بوابة الجاهزية');

select act_as('c2222222-2222-2222-2222-222222222222'::uuid);
select is(fn_launch_readiness() ->> 'code', 'forbidden', 'ولا المشرف');

select act_as('c3333333-3333-3333-3333-333333333333'::uuid);
select is((fn_launch_readiness() -> 'ok')::text, 'true', 'مدير النظام يراها');

select cmp_ok(
  jsonb_array_length(fn_launch_readiness() #> '{data,checks}'),
  '>=', 8, 'تفحص ثمانية بنود على الأقل'
);

/*
 * كل بند يحمل أثره لو نقص. بوابة تقول «فشل» بلا أثر تُقرأ تحذيرًا اختياريًا،
 * وهذا بالضبط ما يجعل بندًا مثل «بيانات حساب الإيداع» يُؤجَّل حتى الإطلاق.
 */
select ok(
  not exists (
    select 1 from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
     where length(btrim(coalesce(c ->> 'impact', ''))) < 10),
  'كل بند يشرح أثر نقصه'
);

-- بيانات حساب الإيداع فارغة افتراضيًا (D8) فالبوابة تمنع
select ok(
  not (fn_launch_readiness() #>> '{data,ready}')::boolean,
  'غير جاهز ما دامت بيانات حساب الإيداع فارغة'
);

select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'bank_account'),
  'false', 'وبند الحساب هو الراسب'
);

reset role;
update app_settings set value = '"حساب دوبي الجاري"'::jsonb where key = 'cash.bank_account_label';
update app_settings set value = '"4417"'::jsonb where key = 'cash.bank_account_hint';
insert into public_holidays (holiday_date, label)
values (current_date + 10, 'عطلة اختبار');
set local role authenticated;
select act_as('c3333333-3333-3333-3333-333333333333'::uuid);

select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'bank_account'),
  'true', 'وبعد ضبطها يمرّ'
);

select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'holidays'),
  'true', 'وبند العطل يمرّ بإدخال عطلة قادمة'
);

-- مندوب ومدقّق ومخزون عقارات موجودة في هذا الاختبار
select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'auditor'),
  'true', 'وجود مدقّق ليس مندوبًا يمرّ'
);

/*
 * عميل فعّال بلا رمز سارٍ يعني ملصقًا في شقة لا يفتح شيئًا — وهو عطل لا
 * يظهر في أي رقم تشغيلي حتى يشتكي العميل.
 */
reset role;
insert into properties (id, code, name) values
  ('e1111111-1111-1111-1111-111111111111', 'TSTL1', 'برج الإطلاق');
insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('e2222222-2222-2222-2222-222222222222', 'e1111111-1111-1111-1111-111111111111',
        'بلا رمز', '+96891234511', '1', '1', 'complete', now());
set local role authenticated;
select act_as('c3333333-3333-3333-3333-333333333333'::uuid);

select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'qr_tokens'),
  'false', 'عميل فعّال بلا رمز سارٍ يُرسب البوابة'
);

reset role;
insert into customer_qr_tokens (customer_id, token)
values ('e2222222-2222-2222-2222-222222222222', gen_random_uuid());
set local role authenticated;
select act_as('c3333333-3333-3333-3333-333333333333'::uuid);

select is(
  (select c ->> 'passed'
     from jsonb_array_elements(fn_launch_readiness() #> '{data,checks}') c
    where c ->> 'key' = 'qr_tokens'),
  'true', 'وبإصدار رمز له يمرّ'
);

-- ── سجل الترحيل ──────────────────────────────────────────────────────────
reset role;
insert into private.migration_log (entity, source_id, target_id, action, reason)
values ('order', 'src-1', 'tgt-1', 'status_mapped', 'delivered (نسخة 1) ← completed');
set local role authenticated;

select act_as('c1111111-1111-1111-1111-111111111111'::uuid);
select is(
  (select count(*)::int from fn_migration_log(null)),
  0, 'المندوب لا يقرأ سجل الترحيل'
);

select act_as('c2222222-2222-2222-2222-222222222222'::uuid);
select cmp_ok(
  (select count(*)::int from fn_migration_log(null)),
  '>=', 1, 'والمشرف يقرأه'
);

reset role;
select * from finish();
rollback;
