-- 0020 — تصحيحان ظهرا عند اختبار دورة التسوية.

-- ── 1. المشغّل يحتاج أسماء المندوبين ─────────────────────────────────────
/*
 * كانت سياسة `staff` تسمح بقراءة سجل المرء وحده لمن هو دون `manager`. لكن
 * المشغّل هو مدقّق التسويات، وتقاريره كلها تربط بالمندوب — فكانت تعود فارغة
 * تمامًا لأن الربط بـ`staff` يُسقط الصفوف غير المرئية.
 *
 * الفجوة صامتة: لا خطأ صلاحية، فقط تقرير خالٍ.
 */
drop policy if exists staff_read_self_or_admin on staff;
create policy staff_read_self_or_operator on staff
  for select to authenticated
  using (user_id = auth.uid() or auth_role_at_least('operator'));

-- ── 2. تحصيل بعد إيداع اليوم ─────────────────────────────────────────────
/*
 * مندوب أودع نقده السادسة مساءً ثم حصّل مبلغًا آخر الثامنة كان يُرفض بـ
 * settlement_closed ويعجز عن التسجيل بقية اليوم — عقوبة على الانضباط.
 *
 * الصواب أن التحصيل اللاحق يفتح تسوية يوم العمل التالي، كما ينص التصميم:
 * التسوية المُسلَّمة لا تقبل تحصيلات جديدة، لكن المندوب لا يُمنع من العمل.
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

  -- الحجب من عدم الإيداع لا من تأخر الاعتماد، وبأيام العمل لا التقويمية
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

  -- أول تسوية مفتوحة من تاريخ اليوم فصاعدًا؛ فإن كانت تسوية اليوم مُسلَّمة
  -- فُتحت تسوية يوم تالٍ بدل رفض التحصيل
  select * into v_settlement
    from cash_settlements s
   where s.courier_id = v_actor and s.state = 'open' and s.business_date >= v_date
   order by s.business_date
   limit 1;

  if v_settlement.id is null then
    loop
      begin
        insert into cash_settlements (courier_id, business_date)
        values (v_actor, v_date)
        returning * into v_settlement;
        exit;
      exception
        when unique_violation then
          -- تسوية هذا التاريخ موجودة ومُسلَّمة: جرّب اليوم التالي
          v_date := v_date + 1;
      end;
    end loop;
  else
    v_date := v_settlement.business_date;
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
