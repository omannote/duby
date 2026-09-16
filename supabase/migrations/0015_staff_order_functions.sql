-- 0015 — دوال دورة حياة الطلب للموظفين.
-- تُستدعى بجلسة الموظف (ADR-011): هويته مرتبطة بالتوقيع فلا تُنتحل.

-- ── انتقال يدوي بفحص تفاؤلي ──────────────────────────────────────────────
/*
 * p_expected_status يمنع تعارض موظفَين على الطلب نفسه: من يصل ثانيًا يجد
 * الحالة تغيّرت فيحصل على stale_state وتُعيد واجهته التحميل، بدل أن يدفع
 * الطلب خطوة إضافية لم يقصدها.
 */
create or replace function fn_advance_status(
  p_order_id        uuid,
  p_expected_status order_status,
  p_to_status       order_status
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders;
begin
  if auth_role() is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select * into v_order from orders o where o.id = p_order_id for update;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_order.status <> p_expected_status then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
      'data', jsonb_build_object('actual_status', v_order.status));
  end if;

  -- الانتقالات الميدانية لا تحدث بضغطة زر: لها دالتها الذرّية
  if p_to_status in ('picked_up', 'completed') then
    return jsonb_build_object('ok', false, 'code', 'invalid_transition',
      'message', 'هذه الخطوة تتطلب مسح رمز العميل وصورة في الموقع');
  end if;

  if not order_transition_allowed(v_order.status, p_to_status) then
    return jsonb_build_object('ok', false, 'code', 'invalid_transition');
  end if;

  update orders set status = p_to_status where id = p_order_id
  returning * into v_order;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_order));
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'code', 'invalid_transition');
end;
$$;

-- ── الإلغاء ───────────────────────────────────────────────────────────────
create or replace function fn_cancel_order(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order orders;
  v_actor uuid := auth_staff_id();
begin
  if auth_role() is null then
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

  if not order_transition_allowed(v_order.status, 'cancelled') then
    return jsonb_build_object('ok', false, 'code', 'invalid_transition',
                              'message', 'لا يمكن إلغاء طلب في حالة نهائية');
  end if;

  update orders
     set status = 'cancelled', cancelled_at = now(),
         cancelled_by = v_actor, cancel_reason = btrim(p_reason)
   where id = p_order_id
  returning * into v_order;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_order));
end;
$$;

-- ── الاستلام والتسليم الميدانيان ─────────────────────────────────────────
/*
 * أهم دالة في النظام.
 *
 * المطابقة والتحقق من الدفع وحفظ الصورة وتغيير الحالة كلها داخل كتلة واحدة:
 * تنجح كلها أو لا أثر لها. أي استثناء يُعالج هنا يتراجع بكل ما سبقه في الكتلة.
 *
 * هذا بالضبط ما استهلك أربعة طلبات متتالية في النظام السابق حين كانت العملية
 * خطوات متتابعة يمكن أن تنقطع في المنتصف وتعيد نجاحًا ظاهريًا.
 *
 * ok = true لا تعود إلا وسجل الطلب محفوظ فعلًا بالحالة الجديدة، والسجل المُعاد
 * هو المحفوظ لا المتوقَّع.
 */
create or replace function fn_confirm_field_step(
  p_order_id     uuid,
  p_step         text,              -- pickup | delivery
  p_qr_token     uuid,
  p_storage_path text,
  p_byte_size    int,
  p_sha256       text,
  p_latitude     numeric default null,
  p_longitude    numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor    uuid := auth_staff_id();
  v_order    orders;
  v_customer customers;
  v_expected order_status;
  v_target   order_status;
  v_kind     photo_kind;
begin
  if v_actor is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if p_step = 'pickup' then
    v_expected := 'confirmed'; v_target := 'picked_up';  v_kind := 'pickup';
  elsif p_step = 'delivery' then
    v_expected := 'out_for_delivery'; v_target := 'completed'; v_kind := 'delivery';
  else
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  select * into v_order from orders o where o.id = p_order_id for update;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_order.status <> v_expected then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
      'data', jsonb_build_object('actual_status', v_order.status));
  end if;

  -- لا تسليم قبل الدفع: مفروض هنا وفي قيد CHECK معًا، طبقتان مستقلتان
  if p_step = 'delivery' and v_order.payment_status <> 'paid' then
    return jsonb_build_object('ok', false, 'code', 'payment_required');
  end if;

  select * into v_customer from customers c where c.id = v_order.customer_id;

  /*
   * المطابقة في الخادم لا في الواجهة: تعديل JavaScript لا يكفي لتجاوزها.
   * الرمز يجب أن يكون الرمز الفعّال الحالي لعميل هذا الطلب تحديدًا.
   */
  if not exists (
    select 1 from customer_qr_tokens t
     where t.token = p_qr_token
       and t.customer_id = v_order.customer_id
       and t.revoked_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'qr_mismatch');
  end if;

  if not v_customer.is_active or v_customer.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'inactive_customer');
  end if;

  begin
    insert into order_photos (order_id, kind, storage_path, byte_size, sha256,
                              taken_by, latitude, longitude)
    values (p_order_id, v_kind, p_storage_path, p_byte_size, p_sha256,
            v_actor, p_latitude, p_longitude);

    if p_step = 'pickup' then
      update orders
         set status = v_target, pickup_confirmed_at = now(), pickup_confirmed_by = v_actor
       where id = p_order_id
      returning * into v_order;
    else
      update orders
         set status = v_target, delivery_confirmed_at = now(), delivery_confirmed_by = v_actor
       where id = p_order_id
      returning * into v_order;
    end if;
  exception
    when unique_violation then
      -- بصمة صورة مكررة: محاولة إعادة استخدام صورة سابقة لتزييف حضور ميداني
      return jsonb_build_object('ok', false, 'code', 'photo_rejected',
                                'message', 'هذه الصورة مستخدمة في خطوة سابقة');
    when check_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_transition');
  end;

  -- السجل المُعاد هو المحفوظ فعلًا، لا حالة متوقَّعة
  return jsonb_build_object('ok', true, 'data', to_jsonb(v_order));
end;
$$;

revoke all on function
  fn_advance_status(uuid, order_status, order_status),
  fn_cancel_order(uuid, text),
  fn_confirm_field_step(uuid, text, uuid, text, int, text, numeric, numeric)
  from public, anon;

grant execute on function
  fn_advance_status(uuid, order_status, order_status),
  fn_cancel_order(uuid, text),
  fn_confirm_field_step(uuid, text, uuid, text, int, text, numeric, numeric)
  to authenticated, service_role;
