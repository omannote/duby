-- يهيّئ قاعدة PostgreSQL عادية لتشبه بيئة Supabase، فتُشغَّل الهجرات
-- واختبارات pgTAP دون الحاجة إلى Supabase CLI أو Docker.
--
-- لا يُطبَّق على staging ولا الإنتاج — هناك توفّر Supabase هذه الكائنات بنفسها.

-- Supabase يضع الامتدادات في مخطط مستقل
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create extension if not exists pgcrypto;
create extension if not exists pgtap;

-- ── الأدوار ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

-- الجداول تُنشأ لاحقًا في الهجرات، فتلتقطها الصلاحيات الافتراضية
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;

/*
 * Supabase يمنح anon وauthenticated كل الصلاحيات على جداول public افتراضيًا،
 * ويُترك للهجرات أن تنزع ما لا يجوز. محاكاته هنا ضرورية لا تجميلية: قاعدة
 * اختبار أشدّ من الإنتاج تُخفي ثغرة بدل أن تكشفها — وهذا ما حدث فعلًا مع
 * صلاحية TRUNCATE التي بقيت لـauthenticated حتى الهجرة 0026.
 */
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;

-- ── مخطط auth ─────────────────────────────────────────────────────────────
create schema if not exists auth;

create table if not exists auth.users (
  id            uuid primary key default gen_random_uuid(),
  email         text unique,
  created_at    timestamptz not null default now()
);

-- تقرأ هوية المستخدم من مطالبات JWT، تمامًا كما في Supabase
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;

/*
 * لا صلاحية لأحد على auth.users — كما في Supabase الحقيقي حيث يملكها
 * supabase_auth_admin ولا anon ولا authenticated ولا حتى service_role يقرؤها.
 * منحُها هنا كان يجعل اختبارات تمرّ محليًا وتفشل في الإنتاج.
 */

-- ── مخطط storage ──────────────────────────────────────────────────────────
create schema if not exists storage;

create table if not exists storage.buckets (
  id      text primary key,
  name    text not null,
  public  boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets(id),
  name       text not null,
  owner      uuid,
  created_at timestamptz not null default now()
);

grant usage on schema storage to service_role;
