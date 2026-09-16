-- رحلة العميل من المسح إلى الطلب.
begin;
select plan(43);

/*
 * حساب الموظف يُنشأ قبل تبديل الدور: auth.users ليست ملكًا لأي من أدوار
 * التطبيق في Supabase — ولا service_role يكتب فيها.
 */
insert into auth.users (id, email)
values ('99999999-9999-9999-9999-999999999999', 'staff@test.local');

set local role service_role;

insert into properties (id, code, name)
values ('11111111-1111-1111-1111-111111111111', 'TSTJ', 'برج الرحلة');

insert into customers (id, property_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

insert into customer_qr_tokens (customer_id, token)
values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333');

insert into staff (id, user_id, full_name, role)
values ('88888888-8888-8888-8888-888888888888', '99999999-9999-9999-9999-999999999999',
        'سالم الموظف', 'operator');

-- ── المسح ─────────────────────────────────────────────────────────────────
select is(
  fn_scan_qr('00000000-0000-0000-0000-000000000000') ->> 'code',
  'invalid_qr', 'رمز غير موجود يُرفض'
);

select is(
  fn_scan_qr('33333333-3333-3333-3333-333333333333') #>> '{data,profile_status}',
  'incomplete', 'العميل الجديد يحتاج استكمال بياناته'
);

-- صفحة العميل لا تكشف أي بيان تشغيلي
select ok(
  not jsonb_exists(fn_scan_qr('33333333-3333-3333-3333-333333333333') #> '{data}', 'property_id'),
  'الرد لا يحوي معرّف العقار'
);

select ok(
  not jsonb_exists(fn_scan_qr('33333333-3333-3333-3333-333333333333') #> '{data}', 'customer_id'),
  'الرد لا يحوي معرّف العميل'
);

select ok(
  not jsonb_exists(fn_scan_qr('33333333-3333-3333-3333-333333333333') #> '{data}', 'full_name'),
  'الرد لا يحوي اسم العميل'
);

-- كل مسحة تُسجَّل بنتيجتها
select cmp_ok(
  (select count(*)::int from scan_events where result = 'profile_required'),
  '>=', 1, 'المسح يُسجَّل بنتيجته'
);

select is(
  (select result from scan_events where result = 'invalid_qr' limit 1),
  'invalid_qr', 'المسح الفاشل يُسجَّل أيضًا'
);

-- ── الرمز المُبطل يُميَّز عن غير الموجود ──────────────────────────────────
insert into customers (id, property_id)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111');
insert into customer_qr_tokens (customer_id, token, revoked_at, revoked_by, revoke_reason)
values ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555',
        now(), '88888888-8888-8888-8888-888888888888', 'اختبار الإبطال');

select is(
  fn_scan_qr('55555555-5555-5555-5555-555555555555') ->> 'code',
  'revoked_qr', 'الرمز المُبطل يُميَّز عن غير الموجود'
);

-- ── العقار المعطَّل يوقف الرحلة ───────────────────────────────────────────
update properties set is_active = false where id = '11111111-1111-1111-1111-111111111111';

select is(
  fn_scan_qr('33333333-3333-3333-3333-333333333333') ->> 'code',
  'inactive_property', 'العقار المعطَّل يوقف الرحلة'
);

update properties set is_active = true where id = '11111111-1111-1111-1111-111111111111';

-- ── استكمال الملف ─────────────────────────────────────────────────────────
create temp table session_ref as
select (fn_scan_qr('33333333-3333-3333-3333-333333333333') #>> '{data,scan_session_id}')::uuid as sid;

select is(
  fn_complete_profile((select sid from session_ref), 'أحمد', '91234567', '3', '12') ->> 'code',
  'invalid_input', 'يرفض هاتفًا غير موحّد الصيغة'
);

select is(
  fn_complete_profile((select sid from session_ref), 'أ', '+96891234567', '3', '12') ->> 'code',
  'invalid_input', 'يرفض اسمًا أقصر من حرفين'
);

select is(
  fn_complete_profile((select sid from session_ref), 'أحمد', '+96891234567', '', '12') ->> 'code',
  'invalid_input', 'يرفض طابقًا فارغًا'
);

select is(
  (fn_complete_profile((select sid from session_ref), 'أحمد', '+96891234567', '3', '12')
    ->> 'ok')::boolean,
  true, 'يقبل البيانات الكاملة'
);

-- الملف يبقى غير مكتمل حتى نجاح التحقق
select is(
  (select profile_status from customers where id = '22222222-2222-2222-2222-222222222222'),
  'incomplete'::profile_status,
  'الملف يبقى غير مكتمل قبل التحقق'
);

-- ── العقار لا يُقبل من العميل ─────────────────────────────────────────────
-- الدالة لا تملك وسيطًا للعقار أصلًا، فلا مكان يستقبله ولو عُدّلت الواجهة
select is(
  (select count(*)::int from information_schema.parameters
    where specific_schema = 'public'
      and specific_name like 'fn_complete_profile%'
      and parameter_name ilike '%property%'),
  0,
  'دالة استكمال الملف بلا أي وسيط للعقار'
);

select is(
  (select property_id from customers where id = '22222222-2222-2222-2222-222222222222'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'العقار يبقى كما حدده الموظف'
);

-- ── إصدار رمز التحقق ──────────────────────────────────────────────────────
select is(
  (fn_issue_otp((select sid from session_ref), 'hash-1') ->> 'ok')::boolean,
  true, 'يُصدر رمز تحقق'
);

-- الرمز لا يُخزَّن نصًّا في أي مكان
select is(
  (select count(*)::int from otp_challenges where code_hash = 'hash-1'),
  1, 'التجزئة وحدها تُخزَّن'
);

select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'otp_challenges'
      and column_name in ('code', 'otp', 'plain_code')),
  0, 'لا عمود لرمز صريح في جدول التحديات'
);

-- ── مهلة إعادة الإرسال ────────────────────────────────────────────────────
select is(
  fn_issue_otp((select sid from session_ref), 'hash-2') ->> 'code',
  'rate_limited', 'إعادة الإرسال الفورية مرفوضة'
);

-- ── حد العميل في الساعة ───────────────────────────────────────────────────
update otp_challenges set created_at = now() - interval '2 minutes'
 where customer_id = '22222222-2222-2222-2222-222222222222';

select is((fn_issue_otp((select sid from session_ref), 'h2') ->> 'ok')::boolean, true, 'إصدار ثانٍ');
update otp_challenges set created_at = now() - interval '2 minutes'
 where customer_id = '22222222-2222-2222-2222-222222222222';
select is((fn_issue_otp((select sid from session_ref), 'h3') ->> 'ok')::boolean, true, 'إصدار ثالث');
update otp_challenges set created_at = now() - interval '2 minutes'
 where customer_id = '22222222-2222-2222-2222-222222222222';
select is((fn_issue_otp((select sid from session_ref), 'h4') ->> 'ok')::boolean, true, 'إصدار رابع');
update otp_challenges set created_at = now() - interval '2 minutes'
 where customer_id = '22222222-2222-2222-2222-222222222222';
select is((fn_issue_otp((select sid from session_ref), 'h5') ->> 'ok')::boolean, true, 'إصدار خامس');
update otp_challenges set created_at = now() - interval '2 minutes'
 where customer_id = '22222222-2222-2222-2222-222222222222';

select is(
  fn_issue_otp((select sid from session_ref), 'h6') ->> 'code',
  'otp_blocked', 'الحد السادس خلال ساعة مرفوض'
);

-- ── الرمز الأحدث يُسقط ما قبله ────────────────────────────────────────────
select is(
  (select count(*)::int from otp_challenges
    where customer_id = '22222222-2222-2222-2222-222222222222' and state = 'superseded'),
  4, 'كل رمز جديد يُسقط سابقه'
);

select is(
  (select count(*)::int from otp_challenges
    where customer_id = '22222222-2222-2222-2222-222222222222' and state = 'pending'),
  1, 'تحدٍّ واحد فعّال فقط'
);

-- ── التحقق ────────────────────────────────────────────────────────────────
select is(
  fn_verify_otp((select sid from session_ref), 'wrong', 'sub-hash') ->> 'code',
  'otp_invalid', 'رمز خاطئ يُرفض'
);

select is(
  (fn_verify_otp((select sid from session_ref), 'wrong', 'sub-hash')
    #>> '{data,attempts_remaining}')::int,
  3, 'عدّاد المحاولات ينقص'
);

select is(
  (fn_verify_otp((select sid from session_ref), 'h5', 'sub-hash') ->> 'ok')::boolean,
  true, 'الرمز الصحيح يُقبل'
);

-- الملف يصبح مكتملًا الآن — التحقق إثبات ملكية الرقم
select is(
  (select profile_status from customers where id = '22222222-2222-2222-2222-222222222222'),
  'complete'::profile_status,
  'الملف يكتمل بعد التحقق لا قبله'
);

-- ── لا طلب قبل الصورة ─────────────────────────────────────────────────────
select is(
  (select count(*)::int from orders where customer_id = '22222222-2222-2222-2222-222222222222'),
  0, 'لا يُنشأ طلب بمجرد نجاح التحقق'
);

-- ── إرسال الطلب ───────────────────────────────────────────────────────────
select is(
  fn_submit_order('لا-يوجد', 'p/x.jpg', 1000, 'sha-x') ->> 'code',
  'submission_expired', 'رمز إرسال غير معروف يُرفض'
);

select is(
  (fn_submit_order('sub-hash', 'intake/1.jpg', 90000, 'sha-1') ->> 'ok')::boolean,
  true, 'الطلب يُنشأ بعد رفع الصورة'
);

select is(
  (select count(*)::int from orders where customer_id = '22222222-2222-2222-2222-222222222222'),
  1, 'طلب واحد'
);

select is(
  (select kind from order_photos op
     join orders o on o.id = op.order_id
    where o.customer_id = '22222222-2222-2222-2222-222222222222'),
  'intake'::photo_kind,
  'الصورة مرتبطة بالطلب'
);

-- ── إعادة الإرسال تُعيد الطلب نفسه ────────────────────────────────────────
select is(
  (fn_submit_order('sub-hash', 'intake/2.jpg', 90000, 'sha-2') #>> '{data,duplicate}')::boolean,
  true, 'إعادة الإرسال تُعلَم كمكررة'
);

select is(
  (select count(*)::int from orders where customer_id = '22222222-2222-2222-2222-222222222222'),
  1, 'ولا تُنشئ طلبًا ثانيًا'
);

-- ── تحقق واحد = طلب واحد ─────────────────────────────────────────────────
select is(
  (select count(*)::int from order_submissions
    where customer_id = '22222222-2222-2222-2222-222222222222'),
  1, 'رمز إرسال واحد لكل تحدٍّ'
);

-- ── رحلة العميل المكتمل: تحقق مباشر بلا إدخال بيانات ─────────────────────
select is(
  fn_scan_qr('33333333-3333-3333-3333-333333333333') #>> '{data,profile_status}',
  'complete', 'العميل المكتمل ينتقل مباشرة إلى التحقق'
);

select is(
  fn_scan_qr('33333333-3333-3333-3333-333333333333') #>> '{data,phone_masked}',
  '+968 ****67', 'الهاتف يُعرض مُقنَّعًا'
);

-- ── تسجيل محاولة التلاعب ──────────────────────────────────────────────────
select lives_ok(
  $$ select fn_log_tamper_attempt(
       (select sid from session_ref), 'property_id', 'محاولة', 'req-1') $$,
  'محاولة التلاعب تُسجَّل'
);

select is(
  (select count(*)::int from private.audit_logs where action = 'tamper_attempt'),
  1, 'المحاولة محفوظة في التدقيق'
);

select * from finish();
rollback;
