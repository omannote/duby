-- 0005 — العملاء ورموز QR.

create table if not exists customers (
  id                   uuid primary key default gen_random_uuid(),
  customer_no          bigint generated always as identity,

  -- إلزامي في المخطط نفسه: لا عميل بلا عقار، مهما كان مصدر الطلب
  property_id          uuid not null references properties(id) on delete restrict,

  full_name            text,
  phone                text check (phone ~ '^\+968[0-9]{8}$'),
  floor_number         text check (length(btrim(floor_number)) between 1 and 10),
  apartment_number     text check (length(btrim(apartment_number)) between 1 and 10),
  notes                text,

  profile_status       profile_status not null default 'incomplete',
  profile_completed_at timestamptz,
  is_active            boolean not null default true,
  created_by           uuid references staff(id),
  updated_by           uuid references staff(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,

  -- «مكتمل» تعني أن كل الحقول موجودة فعلًا، لا مجرد وسم
  constraint customers_complete_requires_fields check (
    profile_status = 'incomplete' or (
      full_name is not null and phone is not null
      and floor_number is not null and apartment_number is not null
      and profile_completed_at is not null
    )
  )
);

create unique index if not exists customers_no_idx on customers(customer_no);

-- فهرس جزئي: يمنع تكرار الهاتف بين الفعّالين، ويسمح بإعادة استخدامه بعد التعطيل
create unique index if not exists customers_phone_active_idx
  on customers(phone) where phone is not null and is_active and deleted_at is null;

create index if not exists customers_property_idx
  on customers(property_id) where deleted_at is null;
create index if not exists customers_status_idx
  on customers(profile_status, is_active) where deleted_at is null;

create trigger trg_customers_touch
  before update on customers
  for each row execute function touch_updated_at();

-- ── رموز QR وتاريخها ──────────────────────────────────────────────────────
/*
 * الرمز سجل مستقل لا حقل في customers. هذا يحفظ تاريخه: متى أُصدر ومن أصدره
 * ومتى أُبطل ولماذا — فنستطيع الردّ على من يمسح رمزًا قديمًا برسالة صحيحة
 * «هذا الرمز أُبطل» بدل «رمز غير صالح».
 */
create table if not exists customer_qr_tokens (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references customers(id) on delete cascade,
  token         uuid not null unique default gen_random_uuid(),
  issued_at     timestamptz not null default now(),
  issued_by     uuid references staff(id),
  revoked_at    timestamptz,
  revoked_by    uuid references staff(id),
  revoke_reason text,

  constraint qr_revoke_complete check (
    revoked_at is null
    or (revoked_by is not null and length(btrim(coalesce(revoke_reason, ''))) >= 3)
  )
);

-- رمز فعّال واحد لكل عميل
create unique index if not exists customer_qr_active_idx
  on customer_qr_tokens(customer_id) where revoked_at is null;

create index if not exists customer_qr_token_lookup_idx
  on customer_qr_tokens(token) where revoked_at is null;
