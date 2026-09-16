-- 0014 — دوال رحلة العميل العامة.
--
-- تُستدعى من وظيفة public-qr بـ service_role، لا بجلسة موظف: العميل لا يملك
-- حسابًا، وهويته = رمز QR + جلسة المسح + تحقق OTP. لذلك تأخذ هذه الدوال
-- وسائطها صراحةً، بعكس دوال المرحلة الأولى (ADR-011).
--
-- قاعدة حاكمة: الدالة لا ترى رمز OTP نصًّا أبدًا. الوظيفة تحسب HMAC بالـpepper
-- وتمرّر التجزئة فقط.

-- ── قراءة الإعدادات ───────────────────────────────────────────────────────
create or replace function setting_int(p_key text, p_default int)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (s.value #>> '{}')::int from app_settings s where s.key = p_key), p_default)
$$;

-- ── إقناع الهاتف ──────────────────────────────────────────────────────────
-- العميل يرى آخر رقمين فقط، فيتعرّف على رقمه دون كشفه لمن التقط الملصق.
create or replace function mask_phone(p_phone text)
returns text
language sql
immutable
as $$
  select case when p_phone is null then null
              else '+968 ****' || right(p_phone, 2) end
$$;

-- ── مسح الرمز ─────────────────────────────────────────────────────────────
create or replace function fn_scan_qr(
  p_token      uuid,
  p_ip_hash    text default null,
  p_user_agent text default null,
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token    customer_qr_tokens;
  v_any      customer_qr_tokens;
  v_customer customers;
  v_property properties;
  v_scan     scan_events;
  v_result   text;
  v_last_otp timestamptz;
  v_cooldown int := setting_int('otp.resend_cooldown_seconds', 60);
begin
  select * into v_token from customer_qr_tokens t
   where t.token = p_token and t.revoked_at is null;

  if v_token.id is null then
    -- نميّز «أُبطل» عن «غير موجود»: الأولى تعني أن على العميل طلب رمز جديد
    select * into v_any from customer_qr_tokens t where t.token = p_token;
    v_result := case when v_any.id is null then 'invalid_qr' else 'revoked_qr' end;

    insert into scan_events (qr_token_id, customer_id, ip_hash, user_agent, result, request_id)
    values (v_any.id, v_any.customer_id, p_ip_hash, p_user_agent, v_result, p_request_id);

    return jsonb_build_object('ok', false, 'code', v_result);
  end if;

  select * into v_customer from customers c where c.id = v_token.customer_id;

  if not v_customer.is_active or v_customer.deleted_at is not null then
    insert into scan_events (qr_token_id, customer_id, ip_hash, user_agent, result, request_id)
    values (v_token.id, v_customer.id, p_ip_hash, p_user_agent, 'inactive_customer', p_request_id);
    return jsonb_build_object('ok', false, 'code', 'inactive_customer');
  end if;

  select * into v_property from properties p where p.id = v_customer.property_id;

  if not v_property.is_active or v_property.deleted_at is not null then
    insert into scan_events (qr_token_id, customer_id, ip_hash, user_agent, result, request_id)
    values (v_token.id, v_customer.id, p_ip_hash, p_user_agent, 'inactive_property', p_request_id);
    return jsonb_build_object('ok', false, 'code', 'inactive_property');
  end if;

  v_result := case when v_customer.profile_status = 'complete'
                   then 'scanned' else 'profile_required' end;

  insert into scan_events (qr_token_id, customer_id, ip_hash, user_agent, result, request_id)
  values (v_token.id, v_customer.id, p_ip_hash, p_user_agent, v_result, p_request_id)
  returning * into v_scan;

  select max(o.created_at) into v_last_otp
    from otp_challenges o where o.customer_id = v_customer.id;

  /*
   * لا يُعاد إلى العميل: اسمه، هاتفه كاملًا، العقار، الطابق، رقم الشقة،
   * ولا معرّفه. صفحة العميل لا تكشف أي بيان تشغيلي.
   */
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'scan_session_id', v_scan.scan_session_id,
    'profile_status',  v_customer.profile_status,
    'phone_masked',    mask_phone(v_customer.phone),
    'can_request_otp', v_customer.profile_status = 'complete',
    'resend_available_in', greatest(
      0, v_cooldown - coalesce(extract(epoch from (now() - v_last_otp))::int, v_cooldown))
  ));
end;
$$;

-- ── استكمال الملف ─────────────────────────────────────────────────────────
/*
 * لا وسيط للعقار — لا بالخطأ ولا بالقصد. العقار يُقرأ من سجل العميل وحده،
 * فحتى لو عدّل أحدهم JavaScript وأرسل property_id فلا مكان يستقبله.
 *
 * الملف يبقى «غير مكتمل» حتى نجاح التحقق: إدخال البيانات ليس إثباتًا لملكيتها.
 */
create or replace function fn_complete_profile(
  p_scan_session     uuid,
  p_full_name        text,
  p_phone            text,
  p_floor_number     text,
  p_apartment_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scan     scan_events;
  v_customer customers;
begin
  select * into v_scan from scan_events s where s.scan_session_id = p_scan_session;
  if v_scan.id is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_qr');
  end if;

  select * into v_customer from customers c where c.id = v_scan.customer_id;
  if v_customer.id is null or not v_customer.is_active or v_customer.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'inactive_customer');
  end if;

  if p_phone !~ '^\+968[0-9]{8}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'رقم هاتف عماني غير صالح');
  end if;

  if length(btrim(coalesce(p_full_name, ''))) < 2 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input', 'message', 'الاسم مطلوب');
  end if;

  if length(btrim(coalesce(p_floor_number, ''))) < 1
     or length(btrim(coalesce(p_apartment_number, ''))) < 1 then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'الطابق ورقم الشقة مطلوبان');
  end if;

  if exists (
    select 1 from customers c
     where c.phone = p_phone and c.id <> v_customer.id
       and c.is_active and c.deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_input',
                              'message', 'هذا الرقم مسجّل لعميل آخر');
  end if;

  update customers
     set full_name        = btrim(p_full_name),
         phone            = p_phone,
         floor_number     = btrim(p_floor_number),
         apartment_number = btrim(p_apartment_number)
   where id = v_customer.id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'profile_status', 'incomplete',
    'next', 'request_otp'
  ));
end;
$$;

-- ── إصدار رمز التحقق ──────────────────────────────────────────────────────
create or replace function fn_issue_otp(p_scan_session uuid, p_code_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scan      scan_events;
  v_customer  customers;
  v_challenge otp_challenges;
  v_ttl       int := setting_int('otp.ttl_seconds', 300);
  v_cooldown  int := setting_int('otp.resend_cooldown_seconds', 60);
  v_max_cust  int := setting_int('otp.max_per_hour_customer', 5);
  v_max_ip    int := setting_int('otp.max_per_hour_ip', 20);
  v_last      timestamptz;
  v_count     int;
begin
  select * into v_scan from scan_events s where s.scan_session_id = p_scan_session;
  if v_scan.id is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_qr');
  end if;

  select * into v_customer from customers c where c.id = v_scan.customer_id;
  if v_customer.id is null or not v_customer.is_active or v_customer.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'inactive_customer');
  end if;

  if v_customer.phone is null then
    return jsonb_build_object('ok', false, 'code', 'profile_incomplete');
  end if;

  -- مهلة إعادة الإرسال
  select max(o.created_at) into v_last
    from otp_challenges o where o.customer_id = v_customer.id;

  if v_last is not null and now() - v_last < make_interval(secs => v_cooldown) then
    return jsonb_build_object('ok', false, 'code', 'rate_limited',
      'data', jsonb_build_object(
        'retry_after', v_cooldown - extract(epoch from (now() - v_last))::int));
  end if;

  -- حد العميل في الساعة
  select count(*)::int into v_count
    from otp_challenges o
   where o.customer_id = v_customer.id and o.created_at > now() - interval '1 hour';

  if v_count >= v_max_cust then
    insert into scan_events (customer_id, ip_hash, result)
    values (v_customer.id, v_scan.ip_hash, 'blocked');
    return jsonb_build_object('ok', false, 'code', 'otp_blocked',
                              'message', 'تجاوزت عدد الرسائل المسموح خلال ساعة');
  end if;

  -- حد عنوان الشبكة في الساعة — يمنع الاستنزاف عبر رموز متعددة
  if v_scan.ip_hash is not null then
    select count(*)::int into v_count
      from otp_challenges o
      join scan_events s on s.id = o.scan_event_id
     where s.ip_hash = v_scan.ip_hash and o.created_at > now() - interval '1 hour';

    if v_count >= v_max_ip then
      return jsonb_build_object('ok', false, 'code', 'rate_limited',
                                'message', 'محاولات كثيرة، حاول لاحقًا');
    end if;
  end if;

  -- الرمز السابق يسقط فور إصدار رمز أحدث
  update otp_challenges
     set state = 'superseded'
   where customer_id = v_customer.id and state in ('pending', 'sent');

  insert into otp_challenges (customer_id, scan_event_id, code_hash, phone_snapshot, state, expires_at)
  values (v_customer.id, v_scan.id, p_code_hash, v_customer.phone, 'pending',
          now() + make_interval(secs => v_ttl))
  returning * into v_challenge;

  update scan_events set otp_requested_at = now(), result = 'otp_requested'
   where id = v_scan.id;

  -- الهاتف يعود للوظيفة لترسل الرسالة؛ لا يعود إلى المتصفح
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'challenge_id', v_challenge.id,
    'phone',        v_customer.phone,
    'expires_in',   v_ttl,
    'resend_available_in', v_cooldown,
    'attempts_remaining',  v_challenge.max_attempts
  ));
end;
$$;

create or replace function fn_mark_otp_sent(p_challenge_id uuid, p_sent boolean)
returns void
language sql
security definer
set search_path = public
as $$
  update otp_challenges
     set state = case when p_sent then 'sent'::otp_state else 'failed'::otp_state end
   where id = p_challenge_id and state = 'pending'
$$;

-- ── التحقق من الرمز ───────────────────────────────────────────────────────
create or replace function fn_verify_otp(
  p_scan_session          uuid,
  p_code_hash             text,
  p_submission_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scan       scan_events;
  v_challenge  otp_challenges;
  v_submission order_submissions;
  v_ttl        int := setting_int('submission.ttl_seconds', 900);
begin
  select * into v_scan from scan_events s where s.scan_session_id = p_scan_session;
  if v_scan.id is null then
    return jsonb_build_object('ok', false, 'code', 'invalid_qr');
  end if;

  -- قفل التحدي يمنع استهلاك محاولتين متزامنتين للعدّاد نفسه
  select * into v_challenge
    from otp_challenges o
   where o.scan_event_id = v_scan.id and o.state in ('pending', 'sent')
   order by o.created_at desc
   limit 1
     for update;

  if v_challenge.id is null then
    return jsonb_build_object('ok', false, 'code', 'otp_required');
  end if;

  if v_challenge.expires_at <= now() then
    update otp_challenges set state = 'expired' where id = v_challenge.id;
    return jsonb_build_object('ok', false, 'code', 'otp_expired');
  end if;

  if v_challenge.attempts >= v_challenge.max_attempts then
    update otp_challenges set state = 'blocked' where id = v_challenge.id;
    return jsonb_build_object('ok', false, 'code', 'otp_blocked');
  end if;

  if v_challenge.code_hash <> p_code_hash then
    update otp_challenges set attempts = attempts + 1 where id = v_challenge.id;
    update scan_events set result = 'otp_failed' where id = v_scan.id;

    return jsonb_build_object('ok', false, 'code', 'otp_invalid',
      'data', jsonb_build_object(
        'attempts_remaining', v_challenge.max_attempts - v_challenge.attempts - 1));
  end if;

  update otp_challenges set state = 'verified', verified_at = now() where id = v_challenge.id;

  -- الملف يصبح مكتملًا الآن لا قبله: التحقق هو إثبات ملكية الرقم
  update customers
     set profile_status = 'complete', profile_completed_at = now()
   where id = v_challenge.customer_id and profile_status = 'incomplete';

  update scan_events set verified_at = now(), result = 'verified' where id = v_scan.id;

  /*
   * رمز إرسال واحد لكل تحدٍّ (unique على otp_challenge_id). هذا ما يمنع
   * ازدواج الطلب من تحقق واحد، ويسمح بإعادة محاولة رفع الصورة خلال مهلته
   * دون طلب رمز تحقق جديد.
   */
  insert into order_submissions (otp_challenge_id, customer_id, token_hash, expires_at)
  values (v_challenge.id, v_challenge.customer_id, p_submission_token_hash,
          now() + make_interval(secs => v_ttl))
  on conflict (otp_challenge_id) do update
    set token_hash = excluded.token_hash, expires_at = excluded.expires_at
  returning * into v_submission;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'expires_in', v_ttl,
    'next', 'capture_photo'
  ));
end;
$$;

-- ── إرسال الطلب ───────────────────────────────────────────────────────────
/*
 * الطلب والصورة في معاملة واحدة. الطلب لا يُنشأ عند نجاح التحقق بل بعد رفع
 * الصورة فعلًا — فلا تبقى طلبات بلا محتوى.
 *
 * إعادة الإرسال بنفس الرمز تُعيد الطلب نفسه لا طلبًا جديدًا.
 */
create or replace function fn_submit_order(
  p_submission_token_hash text,
  p_storage_path          text,
  p_byte_size             int,
  p_sha256                text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_submission order_submissions;
  v_customer   customers;
  v_order      orders;
  v_scan       scan_events;
begin
  select * into v_submission
    from order_submissions s where s.token_hash = p_submission_token_hash
     for update;

  if v_submission.id is null then
    return jsonb_build_object('ok', false, 'code', 'submission_expired');
  end if;

  -- إعادة الإرسال تُعيد الطلب الموجود
  if v_submission.consumed_at is not null then
    select * into v_order from orders o where o.id = v_submission.order_id;
    if v_order.id is null then
      return jsonb_build_object('ok', false, 'code', 'submission_consumed');
    end if;
    return jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'order_no', v_order.order_no, 'status', v_order.status,
      'created_at', v_order.created_at, 'duplicate', true));
  end if;

  if v_submission.expires_at <= now() then
    return jsonb_build_object('ok', false, 'code', 'submission_expired');
  end if;

  select * into v_customer from customers c where c.id = v_submission.customer_id;
  if not v_customer.is_active or v_customer.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'inactive_customer');
  end if;

  select s.* into v_scan
    from scan_events s
    join otp_challenges o on o.scan_event_id = s.id
   where o.id = v_submission.otp_challenge_id;

  insert into orders (customer_id, property_id, scan_event_id, submission_id)
  values (v_customer.id, v_customer.property_id, v_scan.id, v_submission.id)
  returning * into v_order;

  insert into order_photos (order_id, kind, storage_path, byte_size, sha256)
  values (v_order.id, 'intake', p_storage_path, p_byte_size, p_sha256);

  update order_submissions
     set consumed_at = now(), order_id = v_order.id
   where id = v_submission.id;

  update scan_events
     set order_submitted_at = now(), result = 'order_submitted'
   where id = v_scan.id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'order_no', v_order.order_no, 'status', v_order.status,
    'created_at', v_order.created_at, 'duplicate', false));
exception
  when unique_violation then
    -- بصمة صورة مكررة: محاولة إعادة استخدام صورة سابقة
    return jsonb_build_object('ok', false, 'code', 'photo_rejected',
                              'message', 'هذه الصورة مستخدمة في طلب سابق');
end;
$$;

-- ── تسجيل محاولات التلاعب ─────────────────────────────────────────────────
-- صفحة العميل لا ترسل property_id أصلًا؛ وصوله يعني تعديل الواجهة.
create or replace function fn_log_tamper_attempt(
  p_scan_session uuid,
  p_field        text,
  p_value        text,
  p_request_id   text default null
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare v_scan scan_events;
begin
  select * into v_scan from scan_events s where s.scan_session_id = p_scan_session;

  insert into private.audit_logs (action, entity, entity_id, after, reason, request_id, ip_hash)
  values ('tamper_attempt', 'scan_events', v_scan.id,
          jsonb_build_object('field', p_field, 'value', left(coalesce(p_value, ''), 200)),
          'حقل غير متوقع من صفحة العميل', p_request_id, v_scan.ip_hash);
end;
$$;

-- هذه الدوال تُستدعى من وظيفة public-qr بـ service_role وحده.
revoke all on function
  fn_scan_qr(uuid, text, text, text),
  fn_complete_profile(uuid, text, text, text, text),
  fn_issue_otp(uuid, text),
  fn_mark_otp_sent(uuid, boolean),
  fn_verify_otp(uuid, text, text),
  fn_submit_order(text, text, int, text),
  fn_log_tamper_attempt(uuid, text, text, text)
  from public, anon, authenticated;

grant execute on function
  fn_scan_qr(uuid, text, text, text),
  fn_complete_profile(uuid, text, text, text, text),
  fn_issue_otp(uuid, text),
  fn_mark_otp_sent(uuid, boolean),
  fn_verify_otp(uuid, text, text),
  fn_submit_order(text, text, int, text),
  fn_log_tamper_attempt(uuid, text, text, text)
  to service_role;

insert into app_settings (key, value, description) values
  ('otp.resend_cooldown_seconds', '60'::jsonb, 'مهلة إعادة إرسال رمز التحقق'),
  ('otp.max_per_hour_ip', '20'::jsonb, 'حد رسائل التحقق لكل عنوان شبكة في الساعة'),
  ('submission.ttl_seconds', '900'::jsonb, 'صلاحية رمز إرسال الطلب')
on conflict (key) do nothing;
