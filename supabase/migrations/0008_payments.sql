-- 0008 — المدفوعات وأحداثها.

create table if not exists payments (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references orders(id) on delete restrict,
  provider            text not null default 'thawani',
  provider_session_id text unique,
  amount_baisa        bigint not null check (amount_baisa > 0),
  currency            text not null default 'OMR',
  status              text not null default 'created',
  checkout_url        text,
  return_token_hash   text unique,
  idempotency_key     text not null unique,
  created_by          uuid references staff(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists payments_order_idx on payments(order_id, created_at desc);

create trigger trg_payments_touch
  before update on payments
  for each row execute function touch_updated_at();

-- safe_payload يحفظ الحقول غير الحساسة فقط من استجابة المزود
create table if not exists payment_events (
  id            bigint generated always as identity primary key,
  payment_id    uuid references payments(id) on delete cascade,
  order_id      uuid not null references orders(id) on delete cascade,
  event_type    text not null,   -- session_created | webhook | polled | manual_cash | reversed
  old_status    text,
  new_status    text,
  provider_ref  text,
  safe_payload  jsonb not null default '{}'::jsonb,
  created_by    uuid references staff(id),
  created_at    timestamptz not null default now()
);

create index if not exists payment_events_order_idx on payment_events(order_id, created_at desc);
