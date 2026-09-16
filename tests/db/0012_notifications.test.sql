-- الإشعارات: الإدراج الذرّي، والتراجع الأسّي، وعزل الفشل عن حالة الطلب.
begin;
select plan(34);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'op@t.local'),
  ('a2222222-2222-2222-2222-222222222222', 'mgr@t.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'خالد المشغّل', 'operator'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'سعيد المشرف', 'manager');

insert into properties (id, code, name)
values ('c1111111-1111-1111-1111-111111111111', 'TSTN', 'برج الإشعارات');
insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
values ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'أحمد', '+96891234577', '1', '3', 'complete', now());
insert into customer_qr_tokens (customer_id, token)
values ('d1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111');

insert into orders (id, customer_id, property_id)
values ('f1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111');

create or replace function act_as(u uuid) returns void language sql as
  $f$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, true)::void $f$;

select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

-- ── الإدراج داخل معاملة تغيّر الحالة ─────────────────────────────────────
select fn_advance_status('f1111111-1111-1111-1111-111111111111', 'new', 'confirmed');

select is(
  (select count(*)::int from private.notification_outbox
    where order_id = 'f1111111-1111-1111-1111-111111111111' and state = 'pending'),
  1, 'تغيّر الحالة يُدرِج إشعارًا في الطابور'
);

select is(
  (select params ->> 0 from private.notification_outbox
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  'لقد تم تأكيد طلبكم.',
  'النص من إعدادات الحالة'
);

select is(
  (select template_name from private.notification_outbox
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  'ar_template', 'القالب المعتمد بمتغير واحد'
);

select is(
  (select jsonb_array_length(params) from private.notification_outbox
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  1, 'متغير واحد فقط — تمرير اثنين يجعل المزود يرفض الإرسال'
);

-- ── الإشعار المعطَّل يُسجَّل skipped لا يُهمَل ────────────────────────────
-- الحالة «جديد» معطّلة افتراضيًا
select is(
  (select count(*)::int from private.notification_outbox
    where idempotency_key like 'status:%:new'),
  0, 'الإدراج عند الإنشاء لا يقع (المحفّز على التحديث فقط)'
);

select act_as('a2222222-2222-2222-2222-222222222222'::uuid);
select fn_update_status_setting('processing', false, 'طلبكم قيد التنفيذ الآن.');
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select fn_confirm_field_step('f1111111-1111-1111-1111-111111111111', 'pickup',
  'e1111111-1111-1111-1111-111111111111', 'pickup/n.jpg', 4000, 'sha-n1');
select fn_advance_status('f1111111-1111-1111-1111-111111111111', 'picked_up', 'processing');

select is(
  (select state from private.notification_outbox
    where idempotency_key = 'status:f1111111-1111-1111-1111-111111111111:processing'),
  'skipped'::outbox_state,
  'الإشعار المعطَّل يُسجَّل skipped للتدقيق'
);

-- ── معاد الأمان ──────────────────────────────────────────────────────────
select is(
  (select count(*)::int from private.notification_outbox
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  3, 'إشعار واحد لكل انتقال'
);

-- ── سحب دفعة ─────────────────────────────────────────────────────────────
set local role service_role;

create temp table claimed as select * from fn_claim_outbox_batch(10);

select cmp_ok((select count(*)::int from claimed), '>=', 2, 'السحب يعيد المستحقات');

select is(
  (select count(*)::int from claimed where template_name <> 'ar_template'),
  0, 'كلها بالقالب المعتمد'
);

-- المسحوب لا يُسحب مرتين
select is(
  (select count(*)::int from fn_claim_outbox_batch(10)),
  0, 'العنصر المسحوب لا يُسحب مجددًا'
);

-- المعطَّل لا يُسحب أصلًا
select is(
  (select count(*)::int from claimed c
     join private.notification_outbox o on o.id = c.id
    where o.idempotency_key like '%:processing'),
  0, 'الإشعار المعطَّل لا يدخل دفعة الإرسال'
);

-- ── النجاح ───────────────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_mark_outbox_sent((select min(id) from claimed), 'msg-1') $$,
  'وسم الإرسال ينجح'
);

select is(
  (select state from private.notification_outbox where id = (select min(id) from claimed)),
  'sent'::outbox_state, 'الحالة تصبح sent'
);

select is(
  (select provider_msg_id from private.notification_outbox where id = (select min(id) from claimed)),
  'msg-1', 'ومعرّف رسالة المزود محفوظ'
);

-- ── الفشل والتراجع الأسّي ────────────────────────────────────────────────
create temp table target as select max(id) as id from claimed;

select is(
  (fn_mark_outbox_failed((select id from target), 'provider_timeout') #>> '{data,state}'),
  'failed', 'الفشل الأول يبقيها قابلة لإعادة المحاولة'
);

select is(
  (select attempts from private.notification_outbox where id = (select id from target)),
  1::smallint, 'عدّاد المحاولات يزيد'
);

select is(
  (select last_error_code from private.notification_outbox where id = (select id from target)),
  'provider_timeout', 'رمز الخطأ محفوظ'
);

-- الجدول: 1د ← 5د ← 15د ← 60د ← 6س
select is(outbox_backoff(1), interval '1 minute',   'تراجع المحاولة الأولى دقيقة');
select is(outbox_backoff(2), interval '5 minutes',  'ثم خمس دقائق');
select is(outbox_backoff(3), interval '15 minutes', 'ثم ربع ساعة');
select is(outbox_backoff(4), interval '60 minutes', 'ثم ساعة');
select is(outbox_backoff(5), interval '6 hours',    'ثم ست ساعات');

select cmp_ok(
  (select next_attempt_at from private.notification_outbox where id = (select id from target)),
  '>', now(),
  'الموعد التالي في المستقبل'
);

-- ── حالة dead بعد الحد ───────────────────────────────────────────────────
select fn_mark_outbox_failed((select id from target), 'e2');
select fn_mark_outbox_failed((select id from target), 'e3');
select fn_mark_outbox_failed((select id from target), 'e4');

select is(
  (fn_mark_outbox_failed((select id from target), 'e5') #>> '{data,state}'),
  'dead', 'بعد خمس محاولات يصبح ميتًا'
);

select is(
  (select count(*)::int from fn_claim_outbox_batch(10)
    where id = (select id from target)),
  0, 'والميت لا يُسحب مجددًا'
);

-- ── الفشل لا يمس حالة الطلب ──────────────────────────────────────────────
select is(
  (select status from orders where id = 'f1111111-1111-1111-1111-111111111111'),
  'processing'::order_status,
  'فشل الإشعار خمس مرات لا يُرجع حالة الطلب'
);

select is(
  (select count(*)::int from order_status_history
    where order_id = 'f1111111-1111-1111-1111-111111111111'),
  4, 'ولا يمس سجل الحالات'
);

-- ── صحة الطابور ──────────────────────────────────────────────────────────
select is(
  (fn_outbox_health() ->> 'dead')::int,
  1, 'تقرير الصحة يعدّ الميت'
);

select cmp_ok(
  (fn_outbox_health() ->> 'sent_last_hour')::int,
  '>=', 1, 'ويعدّ المُرسل'
);

-- ── رمز التحقق لا يمر عبر الطابور ────────────────────────────────────────
-- تخزين الرمز في params يناقض مبدأ عدم تخزينه أصلًا
select is(
  (select count(*)::int from private.notification_outbox where kind = 'otp'),
  0, 'لا عنصر OTP في الطابور إطلاقًا'
);

select is(
  (select count(*)::int from private.notification_outbox
    where params::text ~ '\m[0-9]{6}\M'),
  0, 'ولا رمز من ستة أرقام في أي حمولة'
);

-- ── سجل الإشعارات للموظف ─────────────────────────────────────────────────
reset role;
select act_as('a1111111-1111-1111-1111-111111111111'::uuid);

select cmp_ok(
  (select count(*)::int from fn_order_notifications('f1111111-1111-1111-1111-111111111111')),
  '>=', 3, 'الموظف يرى سجل إشعارات الطلب'
);

-- الطابور في private: لا وصول مباشر ولو للموظف
set local role authenticated;
select throws_ok(
  $$ select * from private.notification_outbox $$,
  '42501', null, 'الطابور نفسه بعيد عن الواجهة'
);
reset role;

-- ── الصلاحية على الإعدادات ───────────────────────────────────────────────
select is(
  fn_update_status_setting('ready', true, 'طلبكم جاهز.') ->> 'code',
  'forbidden', 'المشغّل لا يعدّل إعدادات الإشعارات'
);

select * from finish();
rollback;
