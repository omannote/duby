-- 0013 — دوال المرحلة الأولى: العقارات والعملاء ورموز QR.
--
-- كل دالة تتحقق من دور المستدعي في سطرها الأول. الصلاحية لا تُفترض من مصدر
-- الاستدعاء، ولا تعتمد على إخفاء أزرار في الواجهة.
--
-- كلها تعيد jsonb بالشكل {ok, code?, data?} — حالة العمل في الجسم لا في رمز
-- خطأ يبتلعه العميل.

-- ── العقارات ──────────────────────────────────────────────────────────────
create or replace function fn_upsert_property(
  p_id        uuid,
  p_code      text,
  p_name      text,
  p_address   text default null,
  p_latitude  numeric default null,
  p_longitude numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth_staff_id();
  v_row   properties;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if p_id is null then
    insert into properties (code, name, address, latitude, longitude, created_by, updated_by)
    values (upper(btrim(p_code)), btrim(p_name), nullif(btrim(p_address), ''),
            p_latitude, p_longitude, v_actor, v_actor)
    returning * into v_row;
  else
    update properties
       set code = upper(btrim(p_code)),
           name = btrim(p_name),
           address = nullif(btrim(p_address), ''),
           latitude = p_latitude,
           longitude = p_longitude,
           updated_by = v_actor
     where id = p_id and deleted_at is null
    returning * into v_row;

    if v_row.id is null then
      return jsonb_build_object('ok', false, 'code', 'order_not_found');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'رمز العقار مستخدم مسبقًا');
  when check_violation then
    return jsonb_build_object('ok', false, 'code', 'invalid_input');
end;
$$;

create or replace function fn_set_property_active(p_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row properties;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  update properties
     set is_active = p_active, updated_by = auth_staff_id()
   where id = p_id and deleted_at is null
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
end;
$$;

create or replace function fn_delete_property(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customers int;
  v_row       properties;
begin
  if not auth_role_at_least('admin') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  -- حذف آمن لا يترك عملاء بلا عقار
  select count(*) into v_customers
    from customers c where c.property_id = p_id and c.deleted_at is null;

  if v_customers > 0 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
      'message', format('العقار مرتبط بـ%s عميلًا — انقلهم أولًا', v_customers));
  end if;

  update properties
     set deleted_at = now(), is_active = false, updated_by = auth_staff_id()
   where id = p_id and deleted_at is null
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
end;
$$;

-- ── إنشاء العميل ورمزه ────────────────────────────────────────────────────
/*
 * عملية واحدة: سجل العميل ورمزه معًا، أو لا شيء. العقار إلزامي ويُتحقق من
 * فعاليته هنا — لا يكفي أن يكون المفتاح الأجنبي صالحًا.
 *
 * بقية البيانات فارغة عمدًا: يملؤها العميل عند أول مسح، لا الموظف.
 */
create or replace function fn_create_customer_with_qr(p_property_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor    uuid := auth_staff_id();
  v_customer customers;
  v_token    customer_qr_tokens;
begin
  if auth_role() is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if not exists (
    select 1 from properties p
     where p.id = p_property_id and p.is_active and p.deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'inactive_property');
  end if;

  insert into customers (property_id, created_by, updated_by)
  values (p_property_id, v_actor, v_actor)
  returning * into v_customer;

  insert into customer_qr_tokens (customer_id, issued_by)
  values (v_customer.id, v_actor)
  returning * into v_token;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'customer', to_jsonb(v_customer),
    'qr_token', v_token.token
  ));
end;
$$;

-- ── إعادة إصدار الرمز ─────────────────────────────────────────────────────
-- الرمز القديم يُبطل فورًا مع حفظ تاريخه وسببه، فنعرف عند التشخيص أنه كان
-- صحيحًا يومًا — ويُردّ على من يمسحه برسالة صحيحة لا «رمز غير صالح».
create or replace function fn_reissue_qr(p_customer_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth_staff_id();
  v_token customer_qr_tokens;
begin
  if auth_role() is null then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'سبب إعادة الإصدار إلزامي');
  end if;

  if not exists (select 1 from customers c where c.id = p_customer_id and c.deleted_at is null) then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  update customer_qr_tokens
     set revoked_at = now(), revoked_by = v_actor, revoke_reason = btrim(p_reason)
   where customer_id = p_customer_id and revoked_at is null;

  insert into customer_qr_tokens (customer_id, issued_by)
  values (p_customer_id, v_actor)
  returning * into v_token;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('qr_token', v_token.token));
end;
$$;

-- ── تعطيل العميل ونقله ────────────────────────────────────────────────────
create or replace function fn_set_customer_active(p_customer_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row customers;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  update customers
     set is_active = p_active, updated_by = auth_staff_id()
   where id = p_customer_id and deleted_at is null
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
end;
$$;

create or replace function fn_move_customer_property(p_customer_id uuid, p_property_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row customers;
begin
  if not auth_role_at_least('manager') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if length(btrim(coalesce(p_reason, ''))) < 3 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'سبب نقل العقار إلزامي');
  end if;

  if not exists (
    select 1 from properties p
     where p.id = p_property_id and p.is_active and p.deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'inactive_property');
  end if;

  update customers
     set property_id = p_property_id, updated_by = auth_staff_id()
   where id = p_customer_id and deleted_at is null
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'code', 'order_not_found');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_row));
end;
$$;

/*
 * تُستدعى بجلسة الموظف نفسه، لا بـ service_role.
 *
 * كانت الخطة تنصّ على الاستدعاء بـ service_role من Edge Function، لكن
 * service_role لا يحمل مطالبة `sub`، فـ auth.uid() فارغة و auth_role() تعيد
 * null — أي أن كل دالة كانت سترد `forbidden`. تم إثبات ذلك باختبار مباشر.
 *
 * البديل — تمرير معرّف الموظف كوسيط — يجعل الفاعل قابلًا للانتحال إن انكشفت
 * الدالة يومًا. أما الاستدعاء بجلسة الموظف فيجعل هويته مرتبطة بالتوقيع ولا
 * تُزوَّر، بينما SECURITY DEFINER يتيح للدالة الكتابة رغم أن RLS لا يمنح
 * الواجهة أي صلاحية كتابة مباشرة.
 *
 * الحماية تبقى في ثلاث طبقات: فحص الدور داخل كل دالة، وغياب سياسات الكتابة
 * في RLS، والقيود في المخطط.
 */
revoke all on function
  fn_upsert_property(uuid, text, text, text, numeric, numeric),
  fn_set_property_active(uuid, boolean),
  fn_delete_property(uuid),
  fn_create_customer_with_qr(uuid),
  fn_reissue_qr(uuid, text),
  fn_set_customer_active(uuid, boolean),
  fn_move_customer_property(uuid, uuid, text)
  from public, anon;

grant execute on function
  fn_upsert_property(uuid, text, text, text, numeric, numeric),
  fn_set_property_active(uuid, boolean),
  fn_delete_property(uuid),
  fn_create_customer_with_qr(uuid),
  fn_reissue_qr(uuid, text),
  fn_set_customer_active(uuid, boolean),
  fn_move_customer_property(uuid, uuid, text)
  to authenticated, service_role;
