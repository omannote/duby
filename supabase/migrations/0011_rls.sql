-- 0011 — سياسات RLS والصلاحيات.
--
-- القاعدة الحاكمة: **الواجهة تقرأ ولا تكتب**. كل الكتابة تمر عبر دوال
-- SECURITY DEFINER تُستدعى من Edge Functions بـ service_role.
--
-- هذا يحل جذريًا التعارض الحرج في النظام السابق: دور authenticated بصلاحية
-- قراءة فقط بينما الواجهة تحاول الكتابة، فتفشل العمليات بـ permission denied
-- رغم وجود السياسات.

alter table staff                 enable row level security;
alter table properties            enable row level security;
alter table customers             enable row level security;
alter table customer_qr_tokens    enable row level security;
alter table scan_events           enable row level security;
alter table otp_challenges        enable row level security;
alter table order_submissions     enable row level security;
alter table orders                enable row level security;
alter table order_photos          enable row level security;
alter table order_status_history  enable row level security;
alter table order_status_settings enable row level security;
alter table payments              enable row level security;
alter table payment_events        enable row level security;
alter table cash_settlements      enable row level security;
alter table cash_collections      enable row level security;
alter table public_holidays       enable row level security;

-- ── الصلاحيات الأساسية ────────────────────────────────────────────────────
-- anon لا يملك وصولًا إلى أي جدول. صفحة العميل تعمل عبر Edge Function وحدها.
revoke all on all tables in schema public from anon;

grant select on
  staff, properties, customers, customer_qr_tokens, scan_events,
  orders, order_photos, order_status_history, order_status_settings,
  payments, payment_events, cash_settlements, cash_collections, public_holidays
  to authenticated;

-- otp_challenges و order_submissions: لا قراءة لأحد، ولا حتى للموظف
revoke all on otp_challenges, order_submissions from authenticated;

/*
 * service_role هو الدور الذي تعمل به وظائف Edge؛ يتجاوز RLS ويحتاج صلاحيات
 * الجداول صراحةً. Supabase يمنحها افتراضيًا، ونثبّتها هنا حتى تعمل أي بيئة
 * محلية بنفس السلوك ولا يتباعد الاختبار عن الإنتاج.
 */
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;

-- ── السياسات ──────────────────────────────────────────────────────────────
-- لا سياسة insert/update/delete لأي جدول: service_role يتجاوز RLS وهو الوحيد
-- الذي يكتب. غياب السياسات هنا مقصود لا سهو.

drop policy if exists staff_read_self_or_admin on staff;
create policy staff_read_self_or_admin on staff
  for select to authenticated
  using (user_id = auth.uid() or auth_role_at_least('manager'));

drop policy if exists properties_read on properties;
create policy properties_read on properties
  for select to authenticated using (auth_role() is not null);

drop policy if exists customers_read on customers;
create policy customers_read on customers
  for select to authenticated using (auth_role() is not null);

drop policy if exists qr_tokens_read_active on customer_qr_tokens;
create policy qr_tokens_read_active on customer_qr_tokens
  for select to authenticated using (auth_role() is not null and revoked_at is null);

drop policy if exists scan_events_read on scan_events;
create policy scan_events_read on scan_events
  for select to authenticated using (auth_role() is not null);

drop policy if exists orders_read on orders;
create policy orders_read on orders
  for select to authenticated using (auth_role() is not null);

drop policy if exists order_photos_read on order_photos;
create policy order_photos_read on order_photos
  for select to authenticated using (auth_role() is not null);

drop policy if exists osh_read on order_status_history;
create policy osh_read on order_status_history
  for select to authenticated using (auth_role() is not null);

drop policy if exists status_settings_read on order_status_settings;
create policy status_settings_read on order_status_settings
  for select to authenticated using (auth_role() is not null);

drop policy if exists payments_read on payments;
create policy payments_read on payments
  for select to authenticated using (auth_role() is not null);

drop policy if exists payment_events_read on payment_events;
create policy payment_events_read on payment_events
  for select to authenticated using (auth_role_at_least('manager'));

drop policy if exists holidays_read on public_holidays;
create policy holidays_read on public_holidays
  for select to authenticated using (auth_role() is not null);

-- المندوب يرى تسوياته وتحصيلاته فقط؛ من فوقه يرى الجميع
drop policy if exists settlements_read on cash_settlements;
create policy settlements_read on cash_settlements
  for select to authenticated
  using (auth_role_at_least('operator') or courier_id = auth_staff_id());

drop policy if exists collections_read on cash_collections;
create policy collections_read on cash_collections
  for select to authenticated
  using (auth_role_at_least('operator') or courier_id = auth_staff_id());

-- ── التخزين ───────────────────────────────────────────────────────────────
-- حاوية خاصة بلا سياسات وصول: القراءة حصرًا عبر رابط موقّع تصدره الوظيفة
-- بعد فحص الصلاحية.
insert into storage.buckets (id, name, public)
values ('order-photos', 'order-photos', false)
on conflict (id) do nothing;
