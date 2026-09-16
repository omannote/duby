-- 0006 — المسحات وتحديات التحقق ورموز الإرسال.

create table if not exists scan_events (
  id                 uuid primary key default gen_random_uuid(),
  customer_id        uuid references customers(id) on delete set null,
  qr_token_id        uuid references customer_qr_tokens(id) on delete set null,
  scan_session_id    uuid not null unique default gen_random_uuid(),
  ip_hash            text,
  user_agent         text,
  result             text not null,
  scanned_at         timestamptz not null default now(),
  otp_requested_at   timestamptz,
  verified_at        timestamptz,
  order_submitted_at timestamptz,
  request_id         text
);

create index if not exists scan_events_customer_idx
  on scan_events(customer_id, scanned_at desc);
create index if not exists scan_events_result_idx
  on scan_events(result, scanned_at desc);

-- ── تحديات OTP ────────────────────────────────────────────────────────────
/*
 * code_hash فقط: الرمز الصريح لا يوجد في قاعدة البيانات ولا في السجلات ولا في
 * الاستثناءات. التجزئة HMAC-SHA256 مربوطة بـ qr_token و scan_session و pepper
 * محفوظ في أسرار Edge Functions.
 */
create table if not exists otp_challenges (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references customers(id) on delete cascade,
  scan_event_id  uuid not null references scan_events(id) on delete cascade,
  code_hash      text not null,
  phone_snapshot text not null,
  state          otp_state not null default 'pending',
  attempts       smallint not null default 0 check (attempts between 0 and 10),
  max_attempts   smallint not null default 5,
  expires_at     timestamptz not null,
  verified_at    timestamptz,
  created_at     timestamptz not null default now()
);

create index if not exists otp_customer_idx on otp_challenges(customer_id, created_at desc);
create index if not exists otp_expiry_idx
  on otp_challenges(expires_at) where state in ('pending', 'sent');

-- ── رموز الإرسال ──────────────────────────────────────────────────────────
-- الفهرس الفريد على otp_challenge_id هو ما يمنع ازدواج الطلب من تحقق واحد.
create table if not exists order_submissions (
  id               uuid primary key default gen_random_uuid(),
  otp_challenge_id uuid not null unique references otp_challenges(id) on delete cascade,
  customer_id      uuid not null references customers(id) on delete cascade,
  token_hash       text not null unique,
  expires_at       timestamptz not null,
  consumed_at      timestamptz,
  order_id         uuid,
  created_at       timestamptz not null default now()
);
