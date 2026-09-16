-- 0021 — الإشعارات: الإدراج في الطابور، والإرسال، والتراجع الأسّي.
--
-- المبدأ الحاكم: **الإشعار لا يُرجع حالة الطلب أبدًا**. الحالة حقيقة تشغيلية،
-- والإشعار أثر جانبي. لذلك الإدراج داخل معاملة تغيّر الحالة، والإرسال خارجها.

-- ── جدول التراجع الأسّي ──────────────────────────────────────────────────
-- 1د ← 5د ← 15د ← 60د ← 6س، ثم dead.
create or replace function outbox_backoff(p_attempt int)
returns interval
language sql
immutable
as $$
  select case p_attempt
    when 1 then interval '1 minute'
    when 2 then interval '5 minutes'
    when 3 then interval '15 minutes'
    when 4 then interval '60 minutes'
    else        interval '6 hours'
  end
$$;

create or replace function outbox_max_attempts()
returns int
language sql
stable
security definer
set search_path = public
as $$ select setting_int('notifications.max_attempts', 5) $$;

-- ── الإدراج عند تغيّر الحالة ─────────────────────────────────────────────
/*
 * يعمل داخل معاملة تغيّر الحالة: إما أن يقعا معًا أو لا يقعا. هذا يغلق الفجوة
 * التي كانت في النظام السابق حيث تتغير الحالة دون أن يُجدوَل إشعارها.
 *
 * الإشعار المعطَّل يُدرَج بحالة skipped لا يُهمَل: التدقيق يحتاج أن يعرف أن
 * الإشعار لم يُرسل عمدًا لا سهوًا.
 */
create or replace function trg_orders_enqueue_notification()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_setting  order_status_settings;
  v_customer customers;
  v_message  text;
  v_link     text;
begin
  select * into v_setting from order_status_settings s where s.status = new.status;
  if v_setting.status is null then
    return null;
  end if;

  select * into v_customer from customers c where c.id = new.customer_id;
  if v_customer.phone is null then
    return null;
  end if;

  v_message := v_setting.notification_message;

  /*
   * رابط الدفع يُضاف إلى نص الرسالة لا كمتغير ثانٍ: قالب `ar_template` يقبل
   * متغيرًا واحدًا فقط، وتمرير اثنين يجعل المزود يرفض الإرسال.
   */
  if new.status = 'out_for_delivery' then
    select p.checkout_url into v_link
      from payments p
     where p.order_id = new.id and p.checkout_url is not null
     order by p.created_at desc
     limit 1;

    if v_link is not null then
      v_message := v_message || E'\n\nرابط الدفع:\n' || v_link;
    end if;
  end if;

  insert into private.notification_outbox
    (kind, order_id, customer_id, recipient, template_name, params, idempotency_key, state)
  values (
    'status_update',
    new.id,
    v_customer.id,
    v_customer.phone,
    v_setting.template_name,
    jsonb_build_array(v_message),
    format('status:%s:%s', new.id, new.status),
    case when v_setting.notify_enabled then 'pending'::outbox_state
         else 'skipped'::outbox_state end
  )
  on conflict (idempotency_key) do nothing;

  return null;
end;
$$;

drop trigger if exists trg_orders_enqueue_notification on orders;
create trigger trg_orders_enqueue_notification
  after update of status on orders
  for each row when (old.status is distinct from new.status)
  execute function trg_orders_enqueue_notification();

-- ── سحب دفعة للإرسال ─────────────────────────────────────────────────────
-- SKIP LOCKED يسمح بعمّال متوازين بلا تعارض على العنصر نفسه.
create or replace function fn_claim_outbox_batch(p_limit int default 50)
returns table (
  id              bigint,
  recipient       text,
  template_name   text,
  params          jsonb,
  idempotency_key text,
  attempts        smallint
)
language sql
security definer
set search_path = public, private
as $$
  with claimed as (
    select o.id
      from private.notification_outbox o
     where o.state in ('pending', 'failed')
       and o.next_attempt_at <= now()
     order by o.next_attempt_at
     limit p_limit
       for update skip locked
  )
  update private.notification_outbox o
     set state = 'sending'
    from claimed c
   where o.id = c.id
  returning o.id, o.recipient, o.template_name, o.params, o.idempotency_key, o.attempts
$$;

create or replace function fn_mark_outbox_sent(p_id bigint, p_provider_msg_id text)
returns void
language sql
security definer
set search_path = public, private
as $$
  update private.notification_outbox
     set state = 'sent', sent_at = now(), provider_msg_id = p_provider_msg_id,
         attempts = attempts + 1
   where id = p_id
$$;

/*
 * الفشل لا يمس الطلب إطلاقًا: يزيد المحاولات ويؤجّل، وبعد الحد الأقصى يصبح
 * dead ويُنبَّه عليه. حالة الطلب تبقى كما هي مهما تكرر الفشل.
 */
create or replace function fn_mark_outbox_failed(p_id bigint, p_error_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_row     private.notification_outbox;
  v_attempt int;
begin
  select * into v_row from private.notification_outbox o where o.id = p_id for update;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  v_attempt := v_row.attempts + 1;

  update private.notification_outbox
     set attempts        = v_attempt,
         last_error_code = p_error_code,
         state           = case when v_attempt >= outbox_max_attempts()
                                then 'dead'::outbox_state
                                else 'failed'::outbox_state end,
         next_attempt_at = now() + outbox_backoff(v_attempt)
   where id = p_id
  returning * into v_row;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'state', v_row.state, 'attempts', v_row.attempts,
    'next_attempt_at', v_row.next_attempt_at));
end;
$$;

-- ── صحة الطابور ──────────────────────────────────────────────────────────
create or replace function fn_outbox_health()
returns jsonb
language sql
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'pending',       count(*) filter (where state = 'pending'),
    'failed',        count(*) filter (where state = 'failed'),
    'dead',          count(*) filter (where state = 'dead'),
    'sent_last_hour',count(*) filter (where state = 'sent' and sent_at > now() - interval '1 hour'),
    'stale_pending', count(*) filter (
                       where state in ('pending', 'sending')
                         and created_at < now() - interval '5 minutes')
  )
  from private.notification_outbox
$$;

-- ── سجل الإشعارات لطلب ───────────────────────────────────────────────────
-- الطابور في مخطط private؛ هذه الدالة المنفذ الوحيد للموظف إليه.
create or replace function fn_order_notifications(p_order_id uuid)
returns table (
  id            bigint,
  state         outbox_state,
  template_name text,
  message       text,
  attempts      smallint,
  last_error_code text,
  created_at    timestamptz,
  sent_at       timestamptz
)
language sql
security definer
set search_path = public, private
as $$
  select o.id, o.state, o.template_name, o.params ->> 0, o.attempts,
         o.last_error_code, o.created_at, o.sent_at
    from private.notification_outbox o
   where o.order_id = p_order_id
     and auth_role() is not null
   order by o.created_at
$$;

-- ── إعدادات الإشعارات ────────────────────────────────────────────────────
create or replace function fn_update_status_setting(
  p_status         order_status,
  p_notify_enabled boolean,
  p_message        text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row order_status_settings;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_message, ''))) < 5 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'نص الرسالة قصير جدًا');
  end if;

  update order_status_settings
     set notify_enabled       = p_notify_enabled,
         notification_message = btrim(p_message),
         updated_by           = auth_staff_id()
   where status = p_status
  returning * into v_row;

  if v_row.status is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
end;
$$;

revoke all on function
  fn_claim_outbox_batch(int),
  fn_mark_outbox_sent(bigint, text),
  fn_mark_outbox_failed(bigint, text),
  fn_outbox_health()
  from public, anon, authenticated;

grant execute on function
  fn_claim_outbox_batch(int),
  fn_mark_outbox_sent(bigint, text),
  fn_mark_outbox_failed(bigint, text),
  fn_outbox_health()
  to service_role;

revoke all on function fn_order_notifications(uuid), fn_update_status_setting(order_status, boolean, text)
  from public, anon;
grant execute on function fn_order_notifications(uuid), fn_update_status_setting(order_status, boolean, text)
  to authenticated, service_role;

insert into app_settings (key, value, description) values
  ('notifications.max_attempts', '5'::jsonb, 'محاولات الإرسال قبل اعتبار الإشعار ميتًا'),
  ('notifications.batch_size', '50'::jsonb, 'حجم دفعة الإرسال')
on conflict (key) do nothing;
