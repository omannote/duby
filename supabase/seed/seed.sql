-- بيانات بذرية للتطوير المحلي فقط. لا تُطبَّق على staging أو الإنتاج.
-- الهدف: مطور جديد يرى نظامًا مأهولًا فور التشغيل.

-- ── حسابات موظفين للتطوير ────────────────────────────────────────────────
/*
 * بلا حساب موظف لا تُفتح لوحة الموظفين إطلاقًا: الدخول ينجح ثم تظهر «لا يوجد
 * حساب موظف فعّال» لأن auth_role() تعيد null. فأول ما يحتاجه من يشغّل النظام
 * لأول مرة هو هذه الحسابات، لا البيانات.
 *
 * كلمة المرور واحدة ومعروفة: devpass123
 *
 * حارس مزدوج قبل إنشائها: لا تُنشأ إلا إذا كانت auth.users فارغة تمامًا ولا
 * طلب واحد في القاعدة. أي قاعدة فيها استخدام حقيقي تتخطّى هذه الكتلة، فلا
 * يمكن أن تهبط كلمة مرور معروفة في بيئة مأهولة حتى لو شُغّل الملف بالغلط.
 */
do $$
declare
  v_user uuid;
  v_role staff_role;
  v_name text;
begin
  if exists (select 1 from auth.users) or exists (select 1 from orders) then
    raise notice 'seed: القاعدة مأهولة — تُخطّيت حسابات التطوير';
    return;
  end if;

  foreach v_role in array array['courier', 'operator', 'manager', 'admin']::staff_role[] loop
    v_name := case v_role
                when 'courier'  then 'سالم المندوب'
                when 'operator' then 'مريم المشغّلة'
                when 'manager'  then 'خالد المشرف'
                else 'مدير النظام'
              end;

    /*
     * أعمدة الرموز تُكتب فارغة لا NULL: GoTrue يقرؤها في سلاسل غير قابلة
     * للعدم، فأي NULL فيها يُفشل الدخول بـ«Database error querying schema» —
     * خطأ لا يذكر العمود ولا يدلّ على السبب.
     */
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token,
      raw_app_meta_data, raw_user_meta_data
    )
    values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      v_role || '@duby.local', crypt('devpass123', gen_salt('bf')),
      now(), now(), now(),
      '', '', '', '', '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb
    )
    returning id into v_user;

    -- الهوية مطلوبة لتسجيل الدخول بالبريد في Supabase Auth
    insert into auth.identities (id, user_id, provider_id, identity_data, provider,
                                 last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_user, v_user::text,
            jsonb_build_object('sub', v_user::text, 'email', v_role || '@duby.local',
                               'email_verified', true),
            'email', now(), now(), now());

    insert into staff (user_id, full_name, role) values (v_user, v_name, v_role);
  end loop;

  raise notice 'seed: أربعة حسابات — courier/operator/manager/admin@duby.local · devpass123';
end $$;

insert into public_holidays (holiday_date, label) values
  ('2026-01-01', 'رأس السنة'),
  ('2026-11-18', 'العيد الوطني')
on conflict (holiday_date) do nothing;

insert into properties (code, name, address, latitude, longitude) values
  ('BRJ1', 'برج النهضة',  'الخوير، مسقط',  23.588000, 58.382900),
  ('BRJ2', 'مجمع الواحة', 'الغبرة، مسقط',  23.601000, 58.430000),
  ('BRJ3', 'أبراج السيفة', 'القرم، مسقط',   23.613000, 58.470000)
on conflict (code) do nothing;

-- عملاء في حالات مختلفة: مكتمل، غير مكتمل، ومعطَّل
do $$
declare
  v_property uuid := (select id from properties where code = 'BRJ1');
  v_customer uuid;
  i          int;
begin
  for i in 1..4 loop
    insert into customers (property_id, full_name, phone, floor_number, apartment_number,
                           profile_status, profile_completed_at)
    values (v_property, 'عميل تجريبي ' || i, '+9689123456' || i, i::text, (10 + i)::text,
            'complete', now())
    returning id into v_customer;

    insert into customer_qr_tokens (customer_id) values (v_customer);
  end loop;

  -- عميلان غير مكتملين: أُنشئ لهما رمز ولم يمسحاه بعد
  for i in 1..2 loop
    insert into customers (property_id)
    values ((select id from properties where code = 'BRJ2'))
    returning id into v_customer;

    insert into customer_qr_tokens (customer_id) values (v_customer);
  end loop;
end $$;

-- ── طلبات في حالات مختلفة ────────────────────────────────────────────────
-- لوحة فارغة لا تُري كيف يعمل النظام: هذه تملأ كل تبويب بصف واحد على الأقل.
do $$
declare
  v_courier  uuid := (select id from staff where role = 'courier');
  v_operator uuid := (select id from staff where role = 'operator');
  v_customer uuid;
  v_order    uuid;
begin
  if v_courier is null or exists (select 1 from orders) then
    return;
  end if;

  -- جديد: وصل للتوّ ولم يُؤكَّد
  select id into v_customer from customers where profile_status = 'complete' order by created_at limit 1;
  insert into orders (customer_id, property_id, status)
  select v_customer, property_id, 'new' from customers where id = v_customer;

  -- قيد التنفيذ: استُلم من العميل
  select id into v_customer from customers where profile_status = 'complete' order by created_at offset 1 limit 1;
  insert into orders (customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by)
  select v_customer, property_id, 'processing', now() - interval '3 hours', v_courier
    from customers where id = v_customer;

  -- خرج للتوصيل: بفاتورة غير مدفوعة — يُظهر بوابة الدفع في الواجهة
  select id into v_customer from customers where profile_status = 'complete' order by created_at offset 2 limit 1;
  insert into orders (customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                      invoice_number, invoice_amount, invoiced_at, invoiced_by)
  select v_customer, property_id, 'out_for_delivery', now() - interval '1 day', v_courier,
         'INV-DEV-001', 6.500, now() - interval '2 hours', v_operator
    from customers where id = v_customer;

  -- مدفوع نقدًا: يُنشئ تحصيلًا وتسوية مفتوحة، فيظهر في تبويب «الصندوق»
  select id into v_customer from customers where profile_status = 'complete' order by created_at offset 3 limit 1;
  insert into orders (customer_id, property_id, status, pickup_confirmed_at, pickup_confirmed_by,
                      invoice_number, invoice_amount, invoiced_at, invoiced_by)
  select v_customer, property_id, 'out_for_delivery', now() - interval '2 days', v_courier,
         'INV-DEV-002', 11.250, now() - interval '2 days', v_operator
    from customers where id = v_customer
  returning id into v_order;

  /*
   * التحصيل عبر دالة النطاق لا بتحديث مباشر: تمرّ البذرة بالمسار نفسه الذي
   * يمرّ به المندوب، فتُنشأ التسوية اليومية والتحصيل كما في التشغيل الفعلي —
   * ويبدأ المشغّل يومه وأمامه تسوية حقيقية ينظر فيها.
   *
   * الإكمال متروك عمدًا: التسليم يتطلب مسح رمز العميل وصورة في الموقع
   * (fn_confirm_field_step)، وتزييفه في البذرة يُنتج طلبًا «مكتملًا» بلا
   * الإثبات الذي يجعل الاكتمال ذا معنى.
   */
  perform set_config('request.jwt.claims',
                     json_build_object('sub', (select user_id from staff where id = v_courier))::text,
                     true);
  perform fn_record_cash_payment(v_order);
  perform set_config('request.jwt.claims', '', true);
end $$;

select format('seed: %s موظفين، %s عقارات، %s عملاء، %s رموز، %s طلبات',
              (select count(*) from staff),
              (select count(*) from properties),
              (select count(*) from customers),
              (select count(*) from customer_qr_tokens),
              (select count(*) from orders)) as status;
