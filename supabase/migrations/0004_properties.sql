-- 0004 — العقارات.
-- اسم العقار تسمية داخلية للتمييز التشغيلي فقط، ولا يُعرض للعميل أبدًا.

create table if not exists properties (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z0-9-]{2,16}$'),
  name        text not null check (length(btrim(name)) between 2 and 120),
  address     text,
  latitude    numeric(9,6) check (latitude between -90 and 90),
  longitude   numeric(9,6) check (longitude between -180 and 180),
  is_active   boolean not null default true,
  created_by  uuid references staff(id),
  updated_by  uuid references staff(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  -- إحداثية واحدة بلا الأخرى لا تحدد موقعًا
  constraint properties_coords_together
    check ((latitude is null) = (longitude is null))
);

create index if not exists properties_active_idx
  on properties(is_active) where deleted_at is null;

create trigger trg_properties_touch
  before update on properties
  for each row execute function touch_updated_at();
