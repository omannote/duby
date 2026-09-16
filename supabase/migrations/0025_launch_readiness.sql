-- 0025 — سجل الترحيل وبوابة جاهزية الإطلاق.

-- ── سجل الترحيل ───────────────────────────────────────────────────────────
/*
 * كل قرار غيّر معنى صف أثناء الترحيل يُكتب هنا: أي طلب هبطت حالته، ومن نُسب
 * إليه تسليم لم يكن مسجّلًا، وأي هاتف نُزع لتكراره. بدون هذا السجل يصبح
 * الترحيل صندوقًا أسود — والسؤال «لماذا صار هذا الطلب كذا؟» بلا جواب.
 */
create table if not exists private.migration_log (
  id         bigint generated always as identity primary key,
  entity     text not null,
  source_id  text,
  target_id  text,
  action     text not null,
  reason     text not null,
  created_at timestamptz not null default now()
);

create index if not exists migration_log_entity_idx on private.migration_log(entity, created_at);

-- المنفذ الوحيد للموظف إلى السجل: محصور بالمشرف فأعلى
create or replace function fn_migration_log(p_entity text default null)
returns table (
  entity     text,
  source_id  text,
  target_id  text,
  action     text,
  reason     text,
  created_at timestamptz
)
language sql
security definer
set search_path = public, private
as $$
  select m.entity, m.source_id, m.target_id, m.action, m.reason, m.created_at
    from private.migration_log m
   where auth_role_at_least('manager')
     and (p_entity is null or m.entity = p_entity)
   order by m.created_at, m.id
$$;

revoke all on function fn_migration_log(text) from public, anon;
grant execute on function fn_migration_log(text) to authenticated, service_role;

-- ── بيانات حساب الإيداع (D8) ─────────────────────────────────────────────
-- مفتاحان فارغان عمدًا: وجودهما فارغين يجعل النقص ظاهرًا في بوابة الجاهزية
insert into app_settings (key, value, description) values
  ('cash.bank_account_label', 'null'::jsonb, 'اسم حساب الإيداع كما يظهر للمندوب'),
  ('cash.bank_account_hint',  'null'::jsonb, 'آخر أربعة أرقام من حساب الإيداع')
on conflict (key) do nothing;

-- ── بوابة جاهزية الإطلاق ──────────────────────────────────────────────────
/*
 * ما لا يُفحص آليًا يُنسى. البنود هنا كلها أشياء لو نقصت لانكسر شيء في أول
 * يوم تشغيل: مندوب لا يعرف أين يودع، مهلة تُحسب بأيام تقويمية، تسوية لا
 * يعتمدها أحد لأن كل الموظفين مندوبون.
 */
create or replace function fn_launch_readiness()
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_ready  boolean;
begin
  if not auth_role_at_least('admin') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  with checks as (
    select 'bank_account' as key,
           'بيانات حساب الإيداع مضبوطة (D8)' as label,
           exists (select 1 from app_settings
                    where key = 'cash.bank_account_label' and value <> 'null'::jsonb)
           and exists (select 1 from app_settings
                        where key = 'cash.bank_account_hint' and value <> 'null'::jsonb) as passed,
           'المندوب لا يعرف أين يودع، وشاشة الإيداع تعرض فراغًا' as impact
    union all
    select 'holidays',
           'عطل رسمية مسجّلة للتسعين يومًا القادمة (D9)',
           exists (select 1 from public_holidays
                    where holiday_date between current_date and current_date + 90),
           'مهلة أيام العمل تُحسب بأيام تقويمية، فتُنذر التسويات قبل أوانها'
    union all
    select 'auditor',
           'مدقّق واحد على الأقل ليس مندوبًا',
           exists (select 1 from staff
                    where role in ('operator','manager','admin')
                      and is_active and deleted_at is null),
           'لا أحد يعتمد تسوية نقدية، فيتوقف التحصيل بعد يوم واحد'
    union all
    select 'courier',
           'مندوب فعّال واحد على الأقل',
           exists (select 1 from staff
                    where role = 'courier' and is_active and deleted_at is null),
           'لا أحد يستلم أو يسلّم ميدانيًا'
    union all
    select 'property',
           'عقار فعّال واحد على الأقل',
           exists (select 1 from properties where is_active and deleted_at is null),
           'لا يمكن ربط عميل بعقار'
    union all
    select 'qr_tokens',
           'كل عميل فعّال يملك رمزًا ساريًا',
           not exists (
             select 1 from customers c
              where c.is_active and c.deleted_at is null
                and not exists (select 1 from customer_qr_tokens t
                                 where t.customer_id = c.id and t.revoked_at is null)),
           'رمز مطبوع في شقة لا يفتح شيئًا'
    union all
    select 'notifications',
           'نصوص إشعارات الحالات مضبوطة',
           not exists (select 1 from order_status_settings
                        where notify_enabled and length(btrim(notification_message)) < 5),
           'إشعار مفعّل برسالة فارغة يصل العميل'
    union all
    select 'outbox_drained',
           'طابور الإشعارات ليس متوقفًا',
           not exists (select 1 from private.notification_outbox
                        where state in ('pending','sending')
                          and created_at < now() - interval '30 minutes'),
           'إشعارات لا تصل، والعميل يظن أن الطلب لم يُستلم'
  )
  select jsonb_agg(jsonb_build_object(
           'key', key, 'label', label, 'passed', passed, 'impact', impact)
         order by passed, key),
         bool_and(passed)
    into v_checks, v_ready
    from checks;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'ready',      v_ready,
    'checks',     v_checks,
    'checked_at', now()));
end;
$$;

revoke all on function fn_launch_readiness() from public, anon;
grant execute on function fn_launch_readiness() to authenticated, service_role;
