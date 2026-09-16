-- 03 — التحويل والتحميل في معاملة واحدة.
--
/*
 * معاملة واحدة لا سبع: إمّا أن يهبط الترحيل كاملًا أو لا يهبط شيء. البديل —
 * تحميل كل كيان على حدة — يترك عند أول فشل قاعدةً نصف مُرحَّلة، وهي أسوأ من
 * قاعدة فارغة لأنها تبدو سليمة.
 *
 * المعرّفات تُحفظ كما هي من المصدر (العملاء، العقارات، الطلبات، الموظفون)
 * فتبقى الروابط قائمة ويصير التحقق والتراجع مسألة مقارنة مباشرة. الأهم:
 * `qr_token` يُنقل بقيمته نفسها — لو تغيّر لأصبحت كل الرموز المطبوعة ورقًا.
 *
 * يُشغَّل بعد اجتياز 02-preflight.sql:
 *   psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f scripts/migration/03-transform-load.sql
 */
begin;

/*
 * يُنفَّذ مرة واحدة. الإدراجات محمية بـon conflict فلا تُضاعف الصفوف، لكن سجل
 * الحالات وسجل الترحيل يقبلان التكرار — وإعادة تشغيل صامتة تُنتج تاريخًا
 * مزدوجًا يصعب تمييزه لاحقًا. للإعادة: 06-rollback.sql أولًا.
 */
do $$
begin
  if exists (
    select 1 from private.migration_log
     where entity = 'run' and action = 'completed'
       and created_at > coalesce((select max(created_at) from private.migration_log
                                   where entity = 'run' and action = 'rolled_back'),
                                 '-infinity'::timestamptz))
  then
    raise exception 'migration_already_run: ترحيل مكتمل قائم. شغّل 06-rollback.sql قبل الإعادة.';
  end if;
end $$;

-- ── 1. الموظفون ───────────────────────────────────────────────────────────
-- الدور من قرار بشري لا من المصدر: القديم لم يميّز بين الميداني والمدقّق
insert into staff (id, user_id, full_name, role, is_active, created_at)
select ls.id, u.id, ls.full_name, d.role, ls.is_active, ls.created_at
  from src.staff ls
  join src.decision_staff_role d on d.email = ls.email
  join auth.users u on lower(u.email) = lower(d.email)
on conflict (id) do nothing;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'staff', ls.id::text, ls.id::text, 'role_assigned',
       format('%s ← %s (قرار D0)', d.role, ls.email)
  from src.staff ls join src.decision_staff_role d on d.email = ls.email;

-- موظف فعّال في المصدر بلا قرار دور لا يُرحَّل — والفحص المسبق منع وصولنا هنا
insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'staff', ls.id::text, null, 'skipped', format('غير فعّال في المصدر (%s)', ls.email)
  from src.staff ls
 where not ls.is_active;

/*
 * بعد إدراج الموظفين لا قبله: الجدول المؤقت يُبنى لحظةَ إنشائه، فلو سبق
 * الإدراج لخرج فارغًا وصار كل فاعل مُرحَّل NULL بصمت.
 */
create temporary table mig_actor on commit drop as
select s.id as staff_id
  from src.decision_migration_actor a
  join src.staff ls on ls.email = a.email
  join staff s on s.id = ls.id
 limit 1;

do $$
begin
  if not exists (select 1 from mig_actor) then
    raise exception 'migration_actor_missing: تعذّر ربط مدقّق الترحيل بسجل موظف';
  end if;
end $$;

-- ── 2. العقارات ───────────────────────────────────────────────────────────
insert into properties (id, code, name, address, latitude, longitude,
                        is_active, deleted_at, created_at)
select
  p.id,
  -- الرمز مطلوب في المخطط الجديد ولا مقابل له في القديم: يُولَّد ثابتًا
  'P' || lpad((row_number() over (order by p.created_at, p.id))::text, 3, '0'),
  p.name, p.address, p.latitude, p.longitude,
  p.is_active, p.deleted_at, p.created_at
  from src.properties p
on conflict (id) do nothing;

-- ── 3. العملاء ────────────────────────────────────────────────────────────
/*
 * الهاتف المكرر: الفهرس الجديد يفرض فرادته بين الفعّالين. من لا يملكه بقرار
 * D يُرحَّل بهاتف فارغ وملف «ناقص» — فيستكمله بنفسه عند أول مسح، وهو أسلم
 * من تعطيله أو تخمين أيّهما الصحيح.
 */
create temporary table mig_customers on commit drop as
select
  c.id,
  coalesce(c.property_id, d.property_id)                            as property_id,
  c.qr_token,
  c.full_name,
  case
    when c.phone is null then null
    when dp.phone is null then c.phone                 -- لا تكرار
    when dp.keep_customer_id = c.id then c.phone       -- صاحب القرار
    else null                                          -- نُزع لتكراره
  end                                                               as phone,
  c.floor_number,
  c.apartment_number,
  c.is_active,
  c.created_at,
  (dp.phone is not null and dp.keep_customer_id <> c.id)            as phone_dropped
from src.customers c
left join src.decision_customer_property d on d.customer_id = c.id
left join src.decision_phone_owner dp on dp.phone = c.phone;

insert into customers (id, property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at, is_active, created_at)
select
  m.id, m.property_id, m.full_name, m.phone, m.floor_number, m.apartment_number,
  -- «مكتمل» تعني أن الحقول الأربعة موجودة فعلًا، لا أن المصدر قال ذلك
  case
    when m.full_name is not null and m.phone is not null
     and m.floor_number is not null and m.apartment_number is not null
    then 'complete'::profile_status
    else 'incomplete'::profile_status
  end,
  case
    when m.full_name is not null and m.phone is not null
     and m.floor_number is not null and m.apartment_number is not null
    then m.created_at
  end,
  m.is_active, m.created_at
  from mig_customers m
on conflict (id) do nothing;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'customer', m.id::text, m.id::text, 'phone_dropped',
       'هاتف مكرر — احتفظ به عميل آخر بقرار D، والملف صار ناقصًا ليُستكمل عند أول مسح'
  from mig_customers m where m.phone_dropped;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'customer', c.id::text, c.id::text, 'property_assigned',
       format('عقار بقرار D1: %s', d.property_id)
  from src.customers c
  join src.decision_customer_property d on d.customer_id = c.id
 where c.property_id is null;

-- ── 4. رموز QR ────────────────────────────────────────────────────────────
-- القيمة نفسها لا رمز جديد: الرموز ملصقة في الشقق ولا يمكن إعادة طباعتها
insert into customer_qr_tokens (customer_id, token, issued_at)
select m.id, m.qr_token, m.created_at
  from mig_customers m
on conflict do nothing;

-- ── 5. المسحات ────────────────────────────────────────────────────────────
insert into scan_events (id, customer_id, qr_token_id, scan_session_id, ip_hash, user_agent,
                         result, scanned_at, otp_requested_at, verified_at, order_submitted_at)
select
  s.id, s.customer_id, t.id, s.scan_session_id, s.ip_hash, s.user_agent,
  s.result, s.scanned_at,
  ch.created_at, ch.verified_at, o.created_at
from src.scan_events s
left join customer_qr_tokens t on t.customer_id = s.customer_id
left join src.otp_challenges ch on ch.scan_event_id = s.id
left join src.orders o on o.scan_event_id = s.id
on conflict (id) do nothing;

-- ── 6. تحديات OTP ─────────────────────────────────────────────────────────
/*
 * الحديثة فقط (٩٠ يومًا) والتي لم تفشل: القديمة بيانات اختبار على الأرجح
 * (D3)، وسياسة الاحتفاظ كانت ستحذفها بعد ليلة واحدة على أي حال.
 */
insert into otp_challenges (id, customer_id, scan_event_id, code_hash, phone_snapshot,
                            state, attempts, expires_at, verified_at, created_at)
select
  ch.id, ch.customer_id, ch.scan_event_id, ch.code_hash, ch.phone_snapshot,
  case ch.status when 'verified' then 'verified'::otp_state
                 when 'expired'  then 'expired'::otp_state
                 else 'pending'::otp_state end,
  least(ch.attempts, 10), ch.expires_at, ch.verified_at, ch.created_at
from src.otp_challenges ch
where ch.created_at > now() - interval '90 days'
  and ch.status <> 'failed'
  and exists (select 1 from scan_events s where s.id = ch.scan_event_id)
on conflict (id) do nothing;

-- ── 7. الطلبات ────────────────────────────────────────────────────────────
create temporary table mig_orders on commit drop as
select
  m.id,
  m.customer_id,
  m.property_id,
  /*
   * القرار D4 قد يهبط بالحالة: «مكتمل» يشترط دفعًا مسجّلًا في النظام الجديد،
   * وهو القيد نفسه الذي كان غيابه يضيّع المال في النظام السابق.
   */
  case
    when m.mapped_status = 'completed' and m.payment_status <> 'paid'
         and du.resolution = 'downgrade' then 'out_for_delivery'
    else m.mapped_status
  end::order_status                                                as status,
  m.scan_event_id,
  coalesce(m.pickup_confirmed_at, m.created_at)                    as pickup_at,
  coalesce(m.pickup_confirmed_by, (select staff_id from mig_actor)) as pickup_by,
  (m.pickup_confirmed_by is null)                                  as pickup_attributed,
  m.delivery_confirmed_at, m.delivery_confirmed_by,
  m.invoice_number, m.invoice_amount, m.paid_at,
  m.payment_status, m.payment_method,
  du.resolution,
  m.cancelled_at, m.cancel_reason,
  dc.reason                                                        as decided_cancel_reason,
  m.created_at, m.updated_at
from src.order_status_mapped m
left join src.decision_unpaid_completed du on du.order_id = m.id
left join src.decision_cancel_reason dc on dc.order_id = m.id;

insert into orders (id, customer_id, property_id, status, status_changed_at,
                    scan_event_id,
                    pickup_confirmed_at, pickup_confirmed_by,
                    delivery_confirmed_at, delivery_confirmed_by,
                    cancelled_at, cancelled_by, cancel_reason,
                    invoice_number, invoice_amount, invoiced_at, invoiced_by,
                    payment_status, payment_method, paid_at, paid_recorded_by,
                    created_at, updated_at)
select
  o.id, o.customer_id, o.property_id, o.status, o.updated_at,
  case when exists (select 1 from scan_events s where s.id = o.scan_event_id)
       then o.scan_event_id end,
  case when o.status in ('new','confirmed','cancelled') then null else o.pickup_at end,
  case when o.status in ('new','confirmed','cancelled') then null else o.pickup_by end,
  case when o.status = 'completed'
       then coalesce(o.delivery_confirmed_at, o.paid_at, o.updated_at) end,
  case when o.status = 'completed'
       then coalesce(o.delivery_confirmed_by, (select staff_id from mig_actor)) end,
  case when o.status = 'cancelled' then coalesce(o.cancelled_at, o.updated_at) end,
  case when o.status = 'cancelled' then (select staff_id from mig_actor) end,
  case when o.status = 'cancelled'
       then coalesce(nullif(btrim(coalesce(o.cancel_reason, '')), ''), o.decided_cancel_reason) end,
  o.invoice_number, o.invoice_amount,
  case when o.invoice_number is not null then o.created_at end,
  case when o.invoice_number is not null then (select staff_id from mig_actor) end,
  -- D4 = mark_paid_cash: النقد حُصِّل خارج النظام ويُوثَّق في التسوية الافتتاحية
  case when o.payment_status = 'paid' or o.resolution = 'mark_paid_cash'
       then 'paid'::payment_status else 'unpaid'::payment_status end,
  case
    when o.payment_status = 'paid' then
      case o.payment_method when 'thawani' then 'thawani'::payment_method
                            else 'cash_on_delivery'::payment_method end
    when o.resolution = 'mark_paid_cash' then 'cash_on_delivery'::payment_method
  end,
  case when o.payment_status = 'paid' or o.resolution = 'mark_paid_cash'
       then coalesce(o.paid_at, o.delivery_confirmed_at, o.updated_at) end,
  case when o.payment_status = 'paid' or o.resolution = 'mark_paid_cash'
       then coalesce(o.delivery_confirmed_by, (select staff_id from mig_actor)) end,
  o.created_at, o.updated_at
from mig_orders o
on conflict (id) do nothing;

-- ما غُيّر معناه يُكتب صراحةً، فيبقى السؤال «لماذا صار هذا الطلب كذا؟» له جواب
insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'order', m.id::text, m.id::text, 'status_mapped',
       format('%s (نسخة %s) ← %s', m.status, m.workflow_version, o.status)
  from src.order_status_mapped m join mig_orders o on o.id = m.id
 where m.status <> o.status::text;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'order', o.id::text, o.id::text, 'payment_decided',
       case o.resolution
         when 'mark_paid_cash' then 'D4: نقد حُصِّل خارج النظام — سُجّل مدفوعًا وأُدرج في التسوية الافتتاحية'
         when 'downgrade'      then 'D4: لم يُسلَّم فعلًا — أُعيد إلى «خرج للتوصيل»'
       end
  from mig_orders o where o.resolution is not null;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'order', o.id::text, o.id::text, 'actor_attributed',
       'لا مستلِم مسجّل في المصدر — نُسب الاستلام لمدقّق الترحيل'
  from mig_orders o
 where o.pickup_attributed and o.status not in ('new','confirmed','cancelled');

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'order', o.id::text, o.id::text, 'actor_attributed',
       'لا مسلِّم مسجّل في المصدر — نُسب التسليم لمدقّق الترحيل'
  from mig_orders o
 where o.status = 'completed' and o.delivery_confirmed_by is null;

-- ── 8. سجل الحالات ────────────────────────────────────────────────────────
/*
 * محفّز الإدراج كتب سطرًا واحدًا لكل طلب بحالته النهائية. نضيف سطرًا صريحًا
 * يقول إن ما قبله مُرحَّل لا مُسجَّل — فلا يُقرأ تاريخ ناقص على أنه كامل.
 */
insert into order_status_history (order_id, from_status, to_status, changed_by, changed_at, reason, context)
select
  o.id, null, o.status, (select staff_id from mig_actor), o.created_at,
  'مُرحَّل من النظام السابق — ما قبل هذا التاريخ غير مسجّل',
  jsonb_build_object('migrated', true, 'source_status', m.status,
                     'workflow_version', m.workflow_version)
from mig_orders o
join src.order_status_mapped m on m.id = o.id;

-- ── 9. المدفوعات ──────────────────────────────────────────────────────────
-- جلسة ثواني تُرحَّل للسجل لا للاستخدام: لا يُستأنف دفع قديم
insert into payments (order_id, provider, provider_session_id, amount_baisa,
                      status, idempotency_key, created_at)
select
  o.id, 'thawani', o.thawani_session_id,
  (o.invoice_amount * 1000)::bigint,
  case when o.payment_status = 'paid' then 'paid' else 'expired' end,
  'migrated:' || o.id::text,
  o.created_at
from src.orders o
where o.thawani_session_id is not null and o.invoice_amount is not null
on conflict do nothing;

-- ── 10. التسوية الافتتاحية ────────────────────────────────────────────────
/*
 * النقد القديم سُلِّم فعلًا خارج النظام. لو رُحِّل مفتوحًا لبدأ كل مندوب بذمة
 * وهمية، ولحُجب عن التحصيل فور الإطلاق (`settlement_closed`). فتُفتح مغلقة
 * معتمدة بفرق صفر، بطريقة تسليم استثنائية وسبب صريح — فتظهر في تقرير
 * الاستثناءات موسومة بأنها ترحيل، وهو الصواب.
 */
create temporary table mig_cash on commit drop as
select
  o.paid_recorded_by                       as courier_id,
  business_date_of(now())                  as business_date,
  sum(o.invoice_amount)                    as total,
  array_agg(o.id)                          as order_ids
from orders o
where o.payment_method = 'cash_on_delivery'
  and o.payment_status = 'paid'
  and o.paid_recorded_by is not null
  and exists (select 1 from mig_orders m where m.id = o.id)
group by o.paid_recorded_by;

insert into cash_settlements (courier_id, business_date, state,
                              expected_amount, declared_amount, confirmed_amount,
                              handover_method, handover_exception_reason, handover_at,
                              handover_note, verified_by, verified_at, notes)
select
  c.courier_id, c.business_date, 'verified',
  c.total, c.total, c.total,
  'office_handover',
  'ترحيل — نقد سابق لتفعيل النظام، لا إيصال بنكي له',
  now(), 'تسوية افتتاحية',
  (select staff_id from mig_actor), now(),
  'تسوية افتتاحية — نقد مُحصَّل قبل تفعيل نظام التسوية، سُوّي خارج النظام'
from mig_cash c
on conflict (courier_id, business_date) do nothing;

insert into cash_collections (order_id, courier_id, amount, business_date, collected_at, settlement_id)
select
  o.id, o.paid_recorded_by, o.invoice_amount, c.business_date, o.paid_at, s.id
from orders o
join mig_cash c on c.courier_id = o.paid_recorded_by
join cash_settlements s
  on s.courier_id = c.courier_id and s.business_date = c.business_date
where o.id = any (c.order_ids)
on conflict do nothing;

insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'cash_settlement', c.courier_id::text, s.id::text, 'opening_settlement',
       format('تسوية افتتاحية معتمدة بفرق صفر لـ%s ر.ع من %s طلبًا',
              c.total, array_length(c.order_ids, 1))
  from mig_cash c
  join cash_settlements s
    on s.courier_id = c.courier_id and s.business_date = c.business_date;

-- ── 11. إعدادات الإشعارات ─────────────────────────────────────────────────
/*
 * `delivered` القديمة تقابل `out_for_delivery` الجديدة في معناها للعميل.
 * القيم السابقة تُلتقط أولًا: هذا التحديث هو الأثر الوحيد الذي يمسّ صفوفًا
 * موجودة أصلًا في الهدف، فبدون لقطة لا يستطيع التراجع إعادتها.
 */
insert into private.migration_log (entity, source_id, target_id, action, reason)
select 'order_status_settings', t.status::text, null, 'message_replaced',
       jsonb_build_object('notify_enabled', t.notify_enabled,
                          'notification_message', t.notification_message)::text
  from order_status_settings t
  join src.order_status_settings s
    on t.status::text = case s.status when 'delivered' then 'out_for_delivery' else s.status end
 where length(btrim(s.message)) >= 5;

update order_status_settings t
   set notify_enabled       = s.notify_enabled,
       notification_message = s.message
  from src.order_status_settings s
 where t.status::text = case s.status when 'delivered' then 'out_for_delivery' else s.status end
   and length(btrim(s.message)) >= 5;

-- ── 12. تسلسل الترقيم ─────────────────────────────────────────────────────
-- الترقيم يتابع من حيث انتهى الترحيل لا من الصفر
select setval(pg_get_serial_sequence('orders', 'order_no'),
              greatest((select coalesce(max(order_no), 0) from orders), 1));
select setval(pg_get_serial_sequence('customers', 'customer_no'),
              greatest((select coalesce(max(customer_no), 0) from customers), 1));

insert into private.migration_log (entity, source_id, target_id, action, reason)
values ('run', null, null, 'completed',
        format('اكتمل الترحيل: %s عميلًا، %s طلبًا، %s موظفًا',
               (select count(*) from customers),
               (select count(*) from orders),
               (select count(*) from staff)));

commit;
