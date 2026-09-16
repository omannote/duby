-- 0001 — الأساس: الامتدادات، مخطط private، وأدوات الفحص.
-- المرحلة صفر: لا جداول نطاق بعد؛ تلك في المرحلة الأولى.

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_stat_statements" with schema extensions;

-- مخطط private: لا وصول منه إلى الواجهة إطلاقًا (لا anon ولا authenticated)
create schema if not exists private;
revoke all on schema private from anon, authenticated;

-- ── إعدادات النظام ────────────────────────────────────────────────────────
create table if not exists app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now()
);

alter table app_settings enable row level security;

-- الواجهة تقرأ ولا تكتب. الكتابة عبر دوال بـ service_role وحده.
create policy app_settings_read on app_settings
  for select to authenticated using (true);

-- ── فحص الصحة ─────────────────────────────────────────────────────────────
-- يثبت أن الواجهة تصل إلى قاعدة البيانات دون كشف أي بيان.
create or replace function health_check()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('ok', true, 'at', now());
$$;

grant execute on function health_check() to anon, authenticated;

-- ── تحديث updated_at ──────────────────────────────────────────────────────
create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_app_settings_touch
  before update on app_settings
  for each row execute function touch_updated_at();

-- ── القيم الافتراضية ──────────────────────────────────────────────────────
insert into app_settings (key, value, description) values
  ('cash.default_handover_method', '"bank_deposit"'::jsonb,
   'الطريقة المعتمدة لإيداع النقد؛ ما عداها استثناء يتطلب سببًا'),
  ('cash.variance_tolerance_omr', '0.100'::jsonb,
   'حد السماح لفرق التسوية قبل اعتبارها متنازعًا عليها'),
  ('cash.max_unhanded_days', '2'::jsonb,
   'أيام عمل قبل حجب المندوب عن التحصيل النقدي'),
  ('cash.weekend_isodow', '[5,6]'::jsonb,
   'الجمعة والسبت — لا تُحتسب في مهلة الإيداع'),
  ('cash.verify_sla_hours', '24'::jsonb,
   'مهلة اعتماد التسوية قبل التنبيه على المدقّق'),
  ('cash.bank_match_sla_days', '7'::jsonb,
   'مهلة المطابقة البنكية قبل التنبيه'),
  ('otp.ttl_seconds', '300'::jsonb, 'صلاحية رمز التحقق'),
  ('otp.max_attempts', '5'::jsonb, 'محاولات التحقق قبل الحجب'),
  ('otp.max_per_hour_customer', '5'::jsonb, 'رسائل التحقق لكل عميل في الساعة'),
  ('photos.retention_days', '180'::jsonb, 'مدة الاحتفاظ بصور الطلبات')
on conflict (key) do nothing;
