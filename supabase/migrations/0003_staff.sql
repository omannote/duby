-- 0003 — الموظفون ودوال الهوية التي تقوم عليها كل سياسات RLS.

create table if not exists staff (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete restrict,
  full_name   text not null check (length(btrim(full_name)) between 2 and 120),
  phone       text check (phone ~ '^\+968[0-9]{8}$'),
  role        staff_role not null default 'courier',
  is_active   boolean not null default true,
  created_by  uuid references staff(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index if not exists staff_role_active_idx
  on staff(role) where deleted_at is null and is_active;

create trigger trg_staff_touch
  before update on staff
  for each row execute function touch_updated_at();

-- ── دوال الهوية ───────────────────────────────────────────────────────────
-- الموظف المعطَّل أو المحذوف تعيد له الدالة null، فترفضه كل السياسات فورًا
-- دون انتظار انتهاء جلسته.

create or replace function auth_staff_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from staff
   where user_id = auth.uid() and is_active and deleted_at is null
$$;

create or replace function auth_role()
returns staff_role
language sql
stable
security definer
set search_path = public
as $$
  select role from staff
   where user_id = auth.uid() and is_active and deleted_at is null
$$;

-- ترتيب الأدوار — لتبسيط فحوص «فأعلى» في السياسات والدوال
create or replace function role_rank(r staff_role)
returns int
language sql
immutable
as $$
  select case r
    when 'courier'  then 1
    when 'operator' then 2
    when 'manager'  then 3
    when 'admin'    then 4
  end
$$;

create or replace function auth_role_at_least(minimum staff_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(role_rank(auth_role()) >= role_rank(minimum), false)
$$;

grant execute on function auth_staff_id(), auth_role(), auth_role_at_least(staff_role)
  to authenticated, service_role;
grant execute on function role_rank(staff_role) to authenticated, service_role;
