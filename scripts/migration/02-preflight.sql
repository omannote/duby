-- 02 — فحوص ما قبل التحميل.
--
/*
 * بوابة: يرفع استثناءً إن بقي قرار واحد ناقصًا أو شذوذ واحد يكسر قيدًا في
 * المخطط الجديد. تشغيله قبل التحويل يعني أن الفشل يقع هنا — في دقيقة، بلا
 * كتابة — لا في منتصف تحميل ليلي.
 *
 * `src.preflight()` قابلة للاستدعاء وحدها لعرض القائمة بلا رفع استثناء.
 */
create or replace function src.preflight()
returns table (severity text, issue text, count int, detail text)
language sql
as $$
  -- D0: كل موظف فعّال يحتاج دورًا صريحًا في النظام الجديد
  select 'blocker', 'موظف فعّال بلا قرار دور (D0)', count(*)::int,
         string_agg(s.email, '، ')
    from src.staff s
   where s.is_active
     and not exists (select 1 from src.decision_staff_role d where d.email = s.email)
  having count(*) > 0

  union all
  -- الحسابات تُنشأ في المشروع الجديد قبل الترحيل: user_id لا يُنقل بين مشروعين
  select 'blocker', 'دور مقرَّر بلا حساب في المشروع الجديد', count(*)::int,
         string_agg(d.email, '، ')
    from src.decision_staff_role d
   where not exists (select 1 from auth.users u where lower(u.email) = lower(d.email))
  having count(*) > 0

  union all
  -- بلا مشغّل ليس مندوبًا يتعذّر اعتماد أي تسوية نقدية بعد الإطلاق
  select 'blocker', 'لا مشغّل أو أعلى غير مندوب (D0)', 1, 'يلزم واحد على الأقل'
   where not exists (
     select 1 from src.decision_staff_role d where d.role in ('operator','manager','admin'))

  union all
  select 'blocker', 'عميل بلا عقار وبلا قرار (D1)', count(*)::int,
         string_agg(c.id::text, '، ')
    from src.customers c
   where c.property_id is null
     and not exists (select 1 from src.decision_customer_property d where d.customer_id = c.id)
  having count(*) > 0

  union all
  select 'blocker', 'عقار مقرَّر غير موجود في المصدر', count(*)::int,
         string_agg(d.customer_id::text, '، ')
    from src.decision_customer_property d
   where not exists (select 1 from src.properties p where p.id = d.property_id)
  having count(*) > 0

  union all
  select 'blocker', 'هاتف مكرر بلا قرار مالك', count(*)::int, string_agg(t.phone, '، ')
    from (select phone from src.customers
           where is_active and phone is not null group by 1 having count(*) > 1) t
   where not exists (select 1 from src.decision_phone_owner d where d.phone = t.phone)
  having count(*) > 0

  union all
  select 'blocker', 'قرار هاتف يشير إلى عميل لا يملكه', count(*)::int, string_agg(d.phone, '، ')
    from src.decision_phone_owner d
   where not exists (
     select 1 from src.customers c where c.id = d.keep_customer_id and c.phone = d.phone)
  having count(*) > 0

  union all
  select 'blocker', 'حالة قديمة لا خريطة لها', count(*)::int,
         string_agg(distinct m.status, '، ')
    from src.order_status_mapped m where m.mapped_status is null
  having count(*) > 0

  union all
  select 'blocker', 'مكتمل غير مدفوع بلا قرار (D4)', count(*)::int,
         string_agg(m.id::text, '، ')
    from src.order_status_mapped m
   where m.mapped_status = 'completed' and m.payment_status <> 'paid'
     and not exists (select 1 from src.decision_unpaid_completed d where d.order_id = m.id)
  having count(*) > 0

  union all
  select 'blocker', 'ملغي بلا سبب وبلا قرار', count(*)::int, string_agg(o.id::text, '، ')
    from src.orders o
   where o.status = 'cancelled'
     and length(btrim(coalesce(o.cancel_reason, ''))) < 3
     and not exists (select 1 from src.decision_cancel_reason d where d.order_id = o.id)
  having count(*) > 0

  union all
  select 'blocker', 'لا مدقّق ترحيل مُعيَّن', 1, 'املأ src.decision_migration_actor'
   where not exists (select 1 from src.decision_migration_actor)

  union all
  select 'blocker', 'مدقّق الترحيل ليس مشرفًا فأعلى', count(*)::int, string_agg(a.email, '، ')
    from src.decision_migration_actor a
   where not exists (
     select 1 from src.decision_staff_role d
      where d.email = a.email and d.role in ('manager','admin'))
  having count(*) > 0

  union all
  select 'blocker', 'رقم فاتورة مكرر', count(*)::int, string_agg(t.invoice_number, '، ')
    from (select invoice_number from src.orders
           where invoice_number is not null group by 1 having count(*) > 1) t
  having count(*) > 0

  union all
  select 'blocker', 'رمز QR مكرر', count(*)::int, string_agg(t.qr_token::text, '، ')
    from (select qr_token from src.customers group by 1 having count(*) > 1) t
  having count(*) > 0

  union all
  -- الهاتف غير المطابق للصيغة يكسر قيد customers_phone_check
  select 'blocker', 'هاتف بصيغة غير مقبولة', count(*)::int, string_agg(c.id::text, '، ')
    from src.customers c
   where c.phone is not null and c.phone !~ '^\+968[0-9]{8}$'
  having count(*) > 0

  union all
  -- القيد الجديد: لا خروج للتوصيل بلا فاتورة. لا قرار بشريًا يصلحه — بيانات ناقصة
  select 'blocker', 'خرج للتوصيل بعد التحويل وبلا رقم فاتورة', count(*)::int,
         string_agg(m.id::text, '، ')
    from src.order_status_mapped m
   where m.mapped_status = 'out_for_delivery' and m.invoice_number is null
  having count(*) > 0

  union all
  select 'blocker', 'طلب يشير إلى عميل غير موجود', count(*)::int, string_agg(o.id::text, '، ')
    from src.orders o
   where not exists (select 1 from src.customers c where c.id = o.customer_id)
  having count(*) > 0

  union all
  /*
   * تحذير لا مانع: المسلِّم غير مسجّل في المصدر. سيُنسب التسليم لمدقّق
   * الترحيل ويُكتب ذلك صراحةً في سجل الحالات وفي سجل الترحيل — لا يُختلق فاعل
   * بصمت.
   */
  select 'warning', 'مكتمل بلا تأكيد تسليم — سيُنسب لمدقّق الترحيل', count(*)::int,
         string_agg(m.id::text, '، ')
    from src.order_status_mapped m
   where m.mapped_status = 'completed'
     and (m.delivery_confirmed_at is null or m.delivery_confirmed_by is null)
  having count(*) > 0

  union all
  select 'warning', 'ما بعد التأكيد بلا تأكيد استلام — سيُنسب لمدقّق الترحيل', count(*)::int,
         string_agg(m.id::text, '، ')
    from src.order_status_mapped m
   where m.mapped_status not in ('new','confirmed','cancelled')
     and (m.pickup_confirmed_at is null or m.pickup_confirmed_by is null)
  having count(*) > 0

  union all
  select 'warning', 'عميل في عقار معطّل أو محذوف', count(*)::int, string_agg(c.id::text, '، ')
    from src.customers c join src.properties p on p.id = c.property_id
   where p.deleted_at is not null or not p.is_active
  having count(*) > 0

  union all
  -- D8: بلا بيانات الحساب لا يعرف المندوب أين يودع
  select 'warning', 'بيانات حساب الإيداع غير مضبوطة (D8)', 1, 'cash.bank_account_label/hint'
   where not exists (
     select 1 from app_settings
      where key = 'cash.bank_account_label' and value::text not in ('null', '""'))

  union all
  -- D9: بلا عطل رسمية تُحسب المهل بأيام تقويمية فعليًا
  select 'warning', 'لا عطل رسمية مسجّلة (D9)', 1, 'public_holidays'
   where not exists (select 1 from public_holidays where holiday_date >= current_date)

  order by 1, 2
$$;

\echo '── فحوص ما قبل التحميل ──────────────────────────────────────────────'
select * from src.preflight();

do $$
declare v_blockers int;
begin
  select count(*) into v_blockers from src.preflight() where severity = 'blocker';

  if v_blockers > 0 then
    raise exception 'preflight_failed: % مانعًا. عالجها في decisions.sql ثم أعد التشغيل.', v_blockers;
  end if;

  raise notice 'اجتاز الفحص المسبق — لا موانع.';
end $$;
