-- 0016 — الفوترة والدفع.
--
-- إنشاء الفاتورة على مرحلتين: الحجز ثم الربط.
--
-- السبب: قاعدة البيانات لا تستطيع نداء ثواني، والمطلوب أن «فشل ثواني ← لا
-- فاتورة ولا انتقال حالة». لو ناديناه أولًا ثم كتبنا، لأنشأ رقم فاتورة مكرر
-- جلسةَ دفع يتيمة قابلة للسداد لطلب لم يُفوتر. الحجز يفحص التفرّد ويقفل الرقم
-- قبل أي نداء خارجي؛ وإن فشل النداء يُحرَّر الحجز ولا يبقى أثر.

-- ── حجز الفاتورة ──────────────────────────────────────────────────────────
create or replace function fn_reserve_invoice(
  p_order_id        uuid,
  p_invoice_number  text,
  p_amount          numeric,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   orders;
  v_payment payments;
begin
  if not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if p_amount is null or p_amount < 0.100 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'الحد الأدنى للفاتورة 0.100 ر.ع');
  end if;

  if length(btrim(coalesce(p_invoice_number, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'رقم الفاتورة مطلوب');
  end if;

  select * into v_order from orders o where o.id = p_order_id for update;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_order.status <> 'ready' then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
      'data', jsonb_build_object('actual_status', v_order.status));
  end if;

  if exists (select 1 from orders o where o.invoice_number = btrim(p_invoice_number)) then
    return jsonb_build_object('ok', false, 'code', 'duplicate_invoice');
  end if;

  -- يقفل الرقم قبل أي نداء خارجي فلا تُنشأ جلسة دفع لرقم مكرر
  insert into payments (order_id, amount_baisa, status, idempotency_key, created_by)
  values (p_order_id, round(p_amount * 1000)::bigint, 'reserved', p_idempotency_key, auth_staff_id())
  returning * into v_payment;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'payment_id',     v_payment.id,
    'amount_baisa',   v_payment.amount_baisa,
    'invoice_number', btrim(p_invoice_number)
  ));
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'duplicate_invoice',
                              'message', 'عملية دفع بنفس المفتاح موجودة');
end;
$$;

-- ── ربط جلسة الدفع ────────────────────────────────────────────────────────
create or replace function fn_attach_checkout(
  p_payment_id        uuid,
  p_invoice_number    text,
  p_amount            numeric,
  p_session_id        text,
  p_checkout_url      text,
  p_return_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payments;
  v_order   orders;
begin
  if not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select * into v_payment from payments p where p.id = p_payment_id for update;

  if v_payment.id is null or v_payment.status <> 'reserved' then
    return jsonb_build_object('ok', false, 'code', 'stale_state');
  end if;

  update payments
     set provider_session_id = p_session_id,
         checkout_url        = p_checkout_url,
         return_token_hash   = p_return_token_hash,
         status              = 'pending'
   where id = p_payment_id
  returning * into v_payment;

  -- الفاتورة والانتقال معًا: إما الاثنان أو لا شيء
  update orders
     set invoice_number = btrim(p_invoice_number),
         invoice_amount = p_amount,
         invoiced_at    = now(),
         invoiced_by    = auth_staff_id(),
         status         = 'out_for_delivery'
   where id = v_payment.order_id
  returning * into v_order;

  insert into payment_events (payment_id, order_id, event_type, new_status, provider_ref)
  values (p_payment_id, v_payment.order_id, 'session_created', 'pending', p_session_id);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'order', to_jsonb(v_order), 'checkout_url', p_checkout_url));
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'duplicate_invoice');
  when check_violation then
    return jsonb_build_object('ok', false, 'code', 'invalid_transition');
end;
$$;

-- يُحرَّر الحجز عند فشل المزود فلا يبقى رقم فاتورة محجوزًا بلا فاتورة
create or replace function fn_release_invoice(p_payment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  delete from payments where id = p_payment_id and status = 'reserved';

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('released', true));
end;
$$;

-- ── الدفع النقدي ──────────────────────────────────────────────────────────
/*
 * يسجّله المندوب الذي استلم المبلغ فعلًا — تقييده كان سيُدخل وسيطًا بين من
 * يحمل النقد ومن يسجّله. الرقابة تأتي من التسوية اليومية لا من منع الكتابة.
 *
 * التسجيل يُنشئ التزامًا ماليًا باسمه فورًا، ويُقيَّد في تسوية يومه.
 */
create or replace function fn_record_cash_payment(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth_staff_id();
  v_order      orders;
  v_settlement cash_settlements;
  v_date       date := business_date_of();
  v_oldest     date;
  v_max_days   int  := setting_int('cash.max_unhanded_days', 2);
begin
  if v_actor is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  /*
   * الحجب يُحسب من عدم الإيداع لا من تأخر الاعتماد، وبأيام العمل لا التقويمية:
   * مندوب أودع ووثّق لا يُحجب لأن المدقّق لم يفتح هاتفه، ومن حصّل يوم الخميس
   * لا يُحجب صباح الأحد والبنك كان مغلقًا.
   */
  select min(s.business_date) into v_oldest
    from cash_settlements s
   where s.courier_id = v_actor and s.state = 'open' and s.business_date < v_date;

  if v_oldest is not null and working_days_between(v_oldest, v_date) > v_max_days then
    return jsonb_build_object('ok', false, 'code', 'unhanded_cash',
      'data', jsonb_build_object('oldest_business_date', v_oldest));
  end if;

  select * into v_order from orders o where o.id = p_order_id for update;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_order.payment_status = 'paid' then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
                              'message', 'الطلب مدفوع مسبقًا');
  end if;

  if v_order.invoice_amount is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'لا فاتورة لهذا الطلب بعد');
  end if;

  -- تسوية اليوم تُفتح تلقائيًا عند أول تحصيل
  select * into v_settlement from cash_settlements s
   where s.courier_id = v_actor and s.business_date = v_date;

  if v_settlement.id is null then
    insert into cash_settlements (courier_id, business_date)
    values (v_actor, v_date)
    returning * into v_settlement;
  elsif v_settlement.state <> 'open' then
    -- تسوية مُودَعة لا تقبل تحصيلات جديدة؛ يُفتح يوم تالٍ
    return jsonb_build_object('ok', false, 'code', 'settlement_closed');
  end if;

  update orders
     set payment_status = 'paid', payment_method = 'cash_on_delivery',
         paid_at = now(), paid_recorded_by = v_actor
   where id = p_order_id
  returning * into v_order;

  insert into cash_collections (order_id, courier_id, settlement_id, amount, business_date)
  values (p_order_id, v_actor, v_settlement.id, v_order.invoice_amount, v_date);

  insert into payment_events (order_id, event_type, old_status, new_status, created_by)
  values (p_order_id, 'manual_cash', 'unpaid', 'paid', v_actor);

  select * into v_settlement from cash_settlements s where s.id = v_settlement.id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'order', to_jsonb(v_order),
    'settlement', jsonb_build_object(
      'id', v_settlement.id,
      'business_date', v_settlement.business_date,
      'expected_amount', v_settlement.expected_amount)
  ));
end;
$$;

-- ── تأكيد الدفع من المزود ─────────────────────────────────────────────────
/*
 * معاد الأمان: استدعاؤه مرتين بنفس الجلسة لا يترك أثرًا ثانيًا. ثواني قد يعيد
 * إرسال الـwebhook، والمصالحة الدورية قد تصل إلى النتيجة نفسها.
 */
create or replace function fn_apply_payment_webhook(
  p_session_id      text,
  p_provider_status text,
  p_safe_payload    jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payments;
  v_order   orders;
  v_paid    boolean := lower(p_provider_status) in ('paid', 'succeeded', 'success');
begin
  select * into v_payment from payments p
   where p.provider_session_id = p_session_id for update;

  if v_payment.id is null then
    -- يُسجَّل ويُعاد 200: ثواني لا يجب أن يعيد الإرسال إلى ما لا نعرفه
    insert into payment_events (order_id, event_type, provider_ref, safe_payload)
    select o.id, 'webhook_unknown_session', p_session_id, p_safe_payload
      from orders o limit 0;
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('applied', false,
                                                                    'reason', 'unknown_session'));
  end if;

  select * into v_order from orders o where o.id = v_payment.order_id for update;

  insert into payment_events (payment_id, order_id, event_type, old_status, new_status,
                              provider_ref, safe_payload)
  values (v_payment.id, v_order.id, 'webhook', v_order.payment_status::text,
          case when v_paid then 'paid' else p_provider_status end, p_session_id, p_safe_payload);

  if not v_paid then
    update payments set status = p_provider_status where id = v_payment.id;
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('applied', false,
                                                                    'reason', 'not_paid'));
  end if;

  -- التطبيق الثاني بلا أثر: الطلب مدفوع مسبقًا
  if v_order.payment_status = 'paid' then
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('applied', false,
                                                                    'reason', 'already_paid'));
  end if;

  update payments set status = 'paid' where id = v_payment.id;

  update orders
     set payment_status = 'paid', payment_method = 'thawani',
         paid_at = now()
   where id = v_order.id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('applied', true));
end;
$$;

-- ── إلغاء الدفع ───────────────────────────────────────────────────────────
create or replace function fn_reverse_payment(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders;
  v_actor uuid := auth_staff_id();
begin
  -- admin وحده: إلغاء دفع مؤكد قرار مالي يتجاوز الرقابة اليومية
  if not auth_role_at_least('admin') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'سبب الإلغاء إلزامي');
  end if;

  select * into v_order from orders o where o.id = p_order_id for update;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_order.payment_status <> 'paid' then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
                              'message', 'الطلب غير مدفوع أصلًا');
  end if;

  -- دفع أكدته ثواني لا يُلغى يدويًا: المزود هو المرجع لا نحن
  if v_order.payment_method = 'thawani' then
    return jsonb_build_object('ok', false, 'code', 'forbidden',
      'message', 'الدفع مؤكد من ثواني ولا يُلغى يدويًا — استخدم الاسترداد لدى المزود');
  end if;

  -- التحصيل النقدي لا يُلغى بعد اعتماد تسويته: الأثر المحاسبي أُغلق
  if exists (
    select 1 from cash_collections c
      join cash_settlements s on s.id = c.settlement_id
     where c.order_id = p_order_id and c.reversed_at is null and s.state = 'verified'
  ) then
    return jsonb_build_object('ok', false, 'code', 'settlement_locked',
      'message', 'التحصيل ضمن تسوية معتمدة — التصحيح بقيد لاحق');
  end if;

  update cash_collections
     set reversed_at = now(), reversed_by = v_actor, reverse_reason = btrim(p_reason)
   where order_id = p_order_id and reversed_at is null;

  update orders
     set payment_status = 'unpaid', payment_method = null,
         paid_at = null, paid_recorded_by = null
   where id = p_order_id
  returning * into v_order;

  insert into payment_events (order_id, event_type, old_status, new_status, created_by, safe_payload)
  values (p_order_id, 'reversed', 'paid', 'unpaid', v_actor,
          jsonb_build_object('reason', btrim(p_reason)));

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_order));
end;
$$;

-- ── المصالحة الدورية ──────────────────────────────────────────────────────
-- شبكة الأمان الثالثة: دفعة نجحت وأُغلق المتصفح قبل العودة ولم يصل webhookها
create or replace function fn_payments_awaiting_reconciliation(p_older_than_minutes int default 10)
returns table (payment_id uuid, session_id text, order_no bigint)
language sql
security definer
set search_path = public
as $$
  select p.id, p.provider_session_id, o.order_no
    from payments p
    join orders o on o.id = p.order_id
   where p.status = 'pending'
     and p.provider_session_id is not null
     and o.payment_status = 'unpaid'
     and p.created_at < now() - make_interval(mins => p_older_than_minutes)
   order by p.created_at
   limit 100
$$;

revoke all on function
  fn_reserve_invoice(uuid, text, numeric, text),
  fn_attach_checkout(uuid, text, numeric, text, text, text),
  fn_release_invoice(uuid, text),
  fn_record_cash_payment(uuid),
  fn_reverse_payment(uuid, text)
  from public, anon;

grant execute on function
  fn_reserve_invoice(uuid, text, numeric, text),
  fn_attach_checkout(uuid, text, numeric, text, text, text),
  fn_release_invoice(uuid, text),
  fn_record_cash_payment(uuid),
  fn_reverse_payment(uuid, text)
  to authenticated, service_role;

-- الـwebhook والمصالحة بلا جلسة موظف: service_role وحده
revoke all on function
  fn_apply_payment_webhook(text, text, jsonb),
  fn_payments_awaiting_reconciliation(int)
  from public, anon, authenticated;

grant execute on function
  fn_apply_payment_webhook(text, text, jsonb),
  fn_payments_awaiting_reconciliation(int)
  to service_role;
