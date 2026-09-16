-- 0009 — التسوية النقدية اليومية.
-- المندوب يستلم النقد ويسجّله ويودعه؛ والاعتماد من operator فأعلى عن بُعد.

-- ── يوم العمل بتوقيت مسقط ─────────────────────────────────────────────────
/*
 * تسليم الساعة 1 صباحًا بتوقيت مسقط هو 21:00 UTC من اليوم السابق. حساب يوم
 * العمل بـUTC كان سيوزّع تحصيلات الليلة الواحدة على يومين.
 */
create or replace function business_date_of(ts timestamptz default now())
returns date
language sql
stable
as $$
  select (ts at time zone 'Asia/Muscat')::date
$$;

create table if not exists public_holidays (
  holiday_date date primary key,
  label        text not null,
  created_by   uuid references staff(id),
  created_at   timestamptz not null default now()
);

/*
 * المهلة بأيام العمل لا بالأيام التقويمية: البنك مغلق في العطل، فمندوب حصّل
 * يوم الخميس كان سيُحجب صباح الأحد بلا ذنب.
 */
-- كل الحقول مؤهّلة صراحةً. خطأ «column reference is ambiguous» عطّل دالة OTP
-- في النظام السابق ولم يُكتشف إلا بعد أن فشل إرسال الرموز فعليًا.
create or replace function weekend_isodow()
returns int[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select array_agg(elem::int)
       from app_settings s
       cross join lateral jsonb_array_elements_text(s.value) as t(elem)
      where s.key = 'cash.weekend_isodow'),
    array[]::int[]
  )
$$;

create or replace function working_days_between(d1 date, d2 date)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when d2 <= d1 then 0 else (
    select count(*)::int
      from generate_series(d1, d2 - 1, interval '1 day') as g(day)
     where extract(isodow from g.day)::int <> all (weekend_isodow())
       and g.day::date not in (select h.holiday_date from public_holidays h)
  ) end
$$;

-- ── حد السماح للفرق ───────────────────────────────────────────────────────
create or replace function tolerance_limit()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (value #>> '{}')::numeric from app_settings where key = 'cash.variance_tolerance_omr'),
    0.100
  )
$$;

-- ── التسويات ──────────────────────────────────────────────────────────────
create table if not exists cash_settlements (
  id               uuid primary key default gen_random_uuid(),
  courier_id       uuid not null references staff(id) on delete restrict,
  business_date    date not null,
  state            settlement_state not null default 'open',

  expected_amount  numeric(12,3) not null default 0,   -- محسوب من النظام
  declared_amount  numeric(12,3),                      -- ما أعلنه المندوب
  confirmed_amount numeric(12,3),                      -- ما أكّده المدقّق من الإثبات
  variance         numeric(12,3)
                   generated always as (confirmed_amount - expected_amount) stored,

  -- الإيداع الموثَّق
  handover_method           handover_method default 'bank_deposit',
  handover_reference        text,   -- رقم إيصال الإيداع — مفتاح المطابقة
  handover_photo_id         uuid references order_photos(id),
  handover_at               timestamptz,
  handover_note             text,
  handover_exception_reason text,   -- إلزامي لغير الإيداع البنكي

  -- الاعتماد عن بُعد
  opened_at   timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references staff(id),
  approved_by uuid references staff(id),
  approved_at timestamptz,

  -- المطابقة البنكية — الحقيقة النهائية
  bank_reference  text,
  bank_matched_at timestamptz,
  bank_matched_by uuid references staff(id),

  variance_reason text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint cash_settlement_one_per_day unique (courier_id, business_date)
);

-- أهم ضابط في هذا الجدول: لا يعتمد أحد تسويته هو، ولو كان admin
alter table cash_settlements drop constraint if exists cash_settlement_no_self_verify;
alter table cash_settlements add constraint cash_settlement_no_self_verify
  check (verified_by is null or verified_by <> courier_id);

alter table cash_settlements drop constraint if exists cash_settlement_no_self_approve;
alter table cash_settlements add constraint cash_settlement_no_self_approve
  check (approved_by is null or approved_by <> courier_id);

alter table cash_settlements drop constraint if exists cash_settlement_handover_complete;
alter table cash_settlements add constraint cash_settlement_handover_complete
  check (state = 'open' or (
    declared_amount is not null and handover_method is not null and handover_at is not null));

-- الإيداع البنكي والتحويل يتطلبان إثباتًا مصوَّرًا ومرجعًا للمطابقة
alter table cash_settlements drop constraint if exists cash_settlement_deposit_needs_proof;
alter table cash_settlements add constraint cash_settlement_deposit_needs_proof
  check (handover_method is null
         or handover_method not in ('bank_deposit', 'transfer')
         or state = 'open'
         or (handover_photo_id is not null
             and length(btrim(coalesce(handover_reference, ''))) >= 3));

-- أي طريقة غير الإيداع البنكي استثناء مرئي يتطلب سببًا مكتوبًا
alter table cash_settlements drop constraint if exists cash_settlement_exception_needs_reason;
alter table cash_settlements add constraint cash_settlement_exception_needs_reason
  check (handover_method is null or handover_method = 'bank_deposit' or state = 'open'
         or length(btrim(coalesce(handover_exception_reason, ''))) >= 3);

alter table cash_settlements drop constraint if exists cash_settlement_verified_complete;
alter table cash_settlements add constraint cash_settlement_verified_complete
  check (state <> 'verified' or (
    confirmed_amount is not null and verified_by is not null and verified_at is not null));

alter table cash_settlements drop constraint if exists cash_settlement_variance_needs_reason;
alter table cash_settlements add constraint cash_settlement_variance_needs_reason
  check (state <> 'verified' or variance = 0
         or length(btrim(coalesce(variance_reason, ''))) >= 3);

alter table cash_settlements drop constraint if exists cash_settlement_large_variance_needs_approval;
alter table cash_settlements add constraint cash_settlement_large_variance_needs_approval
  check (state <> 'verified' or abs(coalesce(variance, 0)) <= tolerance_limit()
         or approved_by is not null);

create index if not exists cash_settlements_courier_idx
  on cash_settlements(courier_id, business_date desc);
create index if not exists cash_settlements_unhanded_idx
  on cash_settlements(business_date) where state = 'open';
create index if not exists cash_settlements_pending_idx
  on cash_settlements(handover_at) where state in ('handed_over', 'disputed');
create index if not exists cash_settlements_unmatched_idx
  on cash_settlements(verified_at)
  where bank_matched_at is null and handover_method in ('bank_deposit', 'transfer');

create trigger trg_cash_settlements_touch
  before update on cash_settlements
  for each row execute function touch_updated_at();

-- ── التحصيلات ─────────────────────────────────────────────────────────────
create table if not exists cash_collections (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null unique references orders(id) on delete restrict,
  courier_id     uuid not null references staff(id) on delete restrict,
  settlement_id  uuid references cash_settlements(id) on delete restrict,
  amount         numeric(12,3) not null check (amount >= 0.100),
  business_date  date not null,
  collected_at   timestamptz not null default now(),

  reversed_at    timestamptz,
  reversed_by    uuid references staff(id),
  reverse_reason text,

  constraint cash_collection_reverse_complete check (
    reversed_at is null
    or (reversed_by is not null and length(btrim(coalesce(reverse_reason, ''))) >= 3)
  )
);

create index if not exists cash_collections_settlement_idx on cash_collections(settlement_id);
create index if not exists cash_collections_courier_idx
  on cash_collections(courier_id, business_date desc);
create unique index if not exists cash_collections_active_order_idx
  on cash_collections(order_id) where reversed_at is null;
