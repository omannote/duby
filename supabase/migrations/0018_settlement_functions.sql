-- 0018 — التسوية النقدية: الإيداع الموثَّق والاعتماد عن بُعد.

-- ── تصحيح: إيصال الإيداع لا يخص طلبًا ────────────────────────────────────
/*
 * `order_photos.order_id` كان إلزاميًا، بينما إيصال الإيداع يخص تسوية لا طلبًا.
 * بقاؤه كذلك كان سيتطلب طلبًا وهميًا لكل إيداع.
 *
 * الجدول يبقى مصدر الصور الوحيد عمدًا: فهرس `sha256` الفريد يصبح عالميًا،
 * فلا يمكن استخدام صورة طلب كإيصال إيداع ولا العكس — ضمانة أقوى من فهرس
 * منفصل لكل جدول.
 */
alter table order_photos alter column order_id drop not null;

alter table order_photos drop constraint if exists order_photos_kind_matches_owner;
alter table order_photos add constraint order_photos_kind_matches_owner
  check ((kind = 'cash_handover') = (order_id is null));

-- ── تسليم النقد وتوثيقه ──────────────────────────────────────────────────
/*
 * المندوب يعمل وحده والمدقّق يعتمد عن بُعد، فالإقفال يقوم على إثبات إيداع
 * موثَّق لا على عدّ حضوري. الإيداع البنكي هو الطريقة المعتمدة لأنه الوحيد
 * الذي يضع طرفًا ثالثًا محايدًا — البنك — بين المندوب والإقفال.
 */
create or replace function fn_hand_over_settlement(
  p_settlement_id     uuid,
  p_declared_amount   numeric,
  p_method            handover_method default 'bank_deposit',
  p_reference         text default null,
  p_photo_path        text default null,
  p_byte_size         int default null,
  p_sha256            text default null,
  p_exception_reason  text default null,
  p_note              text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth_staff_id();
  v_settlement cash_settlements;
  v_photo_id   uuid;
begin
  if v_actor is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select * into v_settlement from cash_settlements s where s.id = p_settlement_id for update;

  if v_settlement.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  -- صاحب التسوية وحده يسلّم نقدها
  if v_settlement.courier_id <> v_actor then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if v_settlement.state <> 'open' then
    return jsonb_build_object('ok', false, 'code', 'settlement_locked');
  end if;

  if p_declared_amount is null or p_declared_amount < 0 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  -- الإيداع البنكي والتحويل: صورة الإيصال ورقمه معًا، والرقم مفتاح المطابقة
  if p_method in ('bank_deposit', 'transfer')
     and (p_photo_path is null or length(btrim(coalesce(p_reference, ''))) < 3) then
    return jsonb_build_object('ok', false, 'code', 'proof_required');
  end if;

  -- ما عدا الإيداع البنكي استثناء مرئي يتطلب سببًا مكتوبًا
  if p_method <> 'bank_deposit' and length(btrim(coalesce(p_exception_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'exception_reason_required');
  end if;

  begin
    if p_photo_path is not null then
      insert into order_photos (order_id, kind, storage_path, byte_size, sha256, taken_by)
      values (null, 'cash_handover', p_photo_path, p_byte_size, p_sha256, v_actor)
      returning id into v_photo_id;
    end if;

    update cash_settlements
       set declared_amount           = p_declared_amount,
           handover_method           = p_method,
           handover_reference        = nullif(btrim(coalesce(p_reference, '')), ''),
           handover_photo_id         = v_photo_id,
           handover_at               = now(),
           handover_exception_reason = nullif(btrim(coalesce(p_exception_reason, '')), ''),
           handover_note             = nullif(btrim(coalesce(p_note, '')), ''),
           state                     = 'handed_over'
     where id = p_settlement_id
    returning * into v_settlement;
  exception
    when unique_violation then
      -- بصمة مستخدمة سابقًا: إعادة استخدام إيصال قديم لإقفال يوم جديد
      return jsonb_build_object('ok', false, 'code', 'proof_reused');
    when check_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_settlement));
end;
$$;

-- ── الاعتماد عن بُعد ─────────────────────────────────────────────────────
/*
 * المدقّق يطابق الإثبات، لا يعدّ النقد. أضعف رقابيًا من العدّ الحضوري —
 * والمطابقة البنكية هي الكاشف الحقيقي لاحقًا.
 *
 * القاعدة التي لا استثناء لها: لا يعتمد أحد تسويته هو، ولو كان admin.
 * مفروضة هنا وفي قيد CHECK معًا: طبقتان مستقلتان.
 */
create or replace function fn_verify_settlement(
  p_settlement_id   uuid,
  p_confirmed_amount numeric,
  p_variance_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth_staff_id();
  v_settlement cash_settlements;
  v_variance   numeric;
  v_tolerance  numeric := tolerance_limit();
begin
  if not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select * into v_settlement from cash_settlements s where s.id = p_settlement_id for update;

  if v_settlement.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_settlement.courier_id = v_actor then
    return jsonb_build_object('ok', false, 'code', 'self_verification');
  end if;

  if v_settlement.state = 'verified' then
    return jsonb_build_object('ok', false, 'code', 'settlement_locked');
  end if;

  if v_settlement.state = 'open' then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
                              'message', 'لم يُسلَّم نقد هذه التسوية بعد');
  end if;

  if p_confirmed_amount is null or p_confirmed_amount < 0 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  v_variance := p_confirmed_amount - v_settlement.expected_amount;

  if v_variance <> 0 and length(btrim(coalesce(p_variance_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'سبب الفرق إلزامي');
  end if;

  update cash_settlements
     set confirmed_amount = p_confirmed_amount,
         verified_by      = v_actor,
         verified_at      = now(),
         variance_reason  = nullif(btrim(coalesce(p_variance_reason, '')), ''),
         -- فرق خارج حد السماح يُرفع للمشرف بدل أن يُعتمد
         state            = case when abs(v_variance) <= v_tolerance
                                 then 'verified'::settlement_state
                                 else 'disputed'::settlement_state end
   where id = p_settlement_id
  returning * into v_settlement;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_settlement));
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'code', 'self_verification');
end;
$$;

-- ── اعتماد فرق خارج السماح ───────────────────────────────────────────────
create or replace function fn_approve_variance(p_settlement_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth_staff_id();
  v_settlement cash_settlements;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  select * into v_settlement from cash_settlements s where s.id = p_settlement_id for update;

  if v_settlement.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_settlement.state <> 'disputed' then
    return jsonb_build_object('ok', false, 'code', 'stale_state');
  end if;

  if v_settlement.courier_id = v_actor then
    return jsonb_build_object('ok', false, 'code', 'self_verification');
  end if;

  update cash_settlements
     set approved_by     = v_actor,
         approved_at     = now(),
         variance_reason = btrim(p_reason),
         state           = 'verified'
   where id = p_settlement_id
  returning * into v_settlement;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_settlement));
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'code', 'self_verification');
end;
$$;

-- ── إلغاء تحصيل ──────────────────────────────────────────────────────────
create or replace function fn_reverse_cash_collection(p_collection_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth_staff_id();
  v_collection cash_collections;
  v_settlement cash_settlements;
begin
  if v_actor is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  select * into v_collection from cash_collections c where c.id = p_collection_id for update;

  if v_collection.id is null or v_collection.reversed_at is not null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  -- المندوب يلغي تحصيله هو؛ من فوقه يلغي أي تحصيل
  if v_collection.courier_id <> v_actor and not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select * into v_settlement from cash_settlements s where s.id = v_collection.settlement_id;

  -- بعد التسليم أُغلق الإقرار؛ وبعد الاعتماد أُغلق الأثر المحاسبي
  if v_settlement.state <> 'open' then
    return jsonb_build_object('ok', false, 'code', 'settlement_locked',
      'message', 'التسوية سُلّمت — التصحيح بقيد لاحق');
  end if;

  update cash_collections
     set reversed_at = now(), reversed_by = v_actor, reverse_reason = btrim(p_reason)
   where id = p_collection_id;

  update orders
     set payment_status = 'unpaid', payment_method = null,
         paid_at = null, paid_recorded_by = null
   where id = v_collection.order_id;

  insert into payment_events (order_id, event_type, old_status, new_status, created_by, safe_payload)
  values (v_collection.order_id, 'reversed', 'paid', 'unpaid', v_actor,
          jsonb_build_object('reason', btrim(p_reason)));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('reversed', true));
end;
$$;

-- ── المطابقة البنكية ─────────────────────────────────────────────────────
-- الاستثناء الوحيد المسموح على تسوية معتمدة: كشف الحساب يصل بعد أيام.
create or replace function fn_match_bank_deposit(p_settlement_id uuid, p_bank_reference text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_settlement cash_settlements;
begin
  if not auth_role_at_least('operator') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_bank_reference, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
  end if;

  select * into v_settlement from cash_settlements s where s.id = p_settlement_id for update;

  if v_settlement.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  if v_settlement.state <> 'verified' then
    return jsonb_build_object('ok', false, 'code', 'stale_state',
                              'message', 'التسوية غير معتمدة بعد');
  end if;

  update cash_settlements
     set bank_reference  = btrim(p_bank_reference),
         bank_matched_at = now(),
         bank_matched_by = auth_staff_id()
   where id = p_settlement_id
  returning * into v_settlement;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_settlement));
end;
$$;

revoke all on function
  fn_hand_over_settlement(uuid, numeric, handover_method, text, text, int, text, text, text),
  fn_verify_settlement(uuid, numeric, text),
  fn_approve_variance(uuid, text),
  fn_reverse_cash_collection(uuid, text),
  fn_match_bank_deposit(uuid, text)
  from public, anon;

grant execute on function
  fn_hand_over_settlement(uuid, numeric, handover_method, text, text, int, text, text, text),
  fn_verify_settlement(uuid, numeric, text),
  fn_approve_variance(uuid, text),
  fn_reverse_cash_collection(uuid, text),
  fn_match_bank_deposit(uuid, text)
  to authenticated, service_role;
