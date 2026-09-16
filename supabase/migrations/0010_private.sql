-- 0010 — التدقيق وطابور الإشعارات. مخطط private: لا وصول من الواجهة إطلاقًا.

create table if not exists private.audit_logs (
  id         bigint generated always as identity primary key,
  actor_id   uuid,
  actor_role staff_role,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  before     jsonb,
  after      jsonb,
  reason     text,
  request_id text,
  ip_hash    text,
  created_at timestamptz not null default now()
);

create index if not exists audit_entity_idx
  on private.audit_logs(entity, entity_id, created_at desc);
create index if not exists audit_actor_idx
  on private.audit_logs(actor_id, created_at desc);

/*
 * params يحوي النص النهائي فقط. رمز OTP لا يمر عبر هذا الطابور إطلاقًا —
 * يُرسل مباشرة ولا يُخزَّن، فوضعه هنا يناقض مبدأ عدم تخزينه.
 */
create table if not exists private.notification_outbox (
  id              bigint generated always as identity primary key,
  kind            text not null,   -- status_update
  order_id        uuid references public.orders(id) on delete cascade,
  customer_id     uuid references public.customers(id) on delete cascade,
  recipient       text not null,
  template_name   text not null,
  params          jsonb not null,
  idempotency_key text not null unique,
  state           outbox_state not null default 'pending',
  attempts        smallint not null default 0,
  next_attempt_at timestamptz not null default now(),
  provider_msg_id text,
  last_error_code text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);

create index if not exists outbox_due_idx
  on private.notification_outbox(next_attempt_at)
  where state in ('pending', 'failed');

revoke all on all tables in schema private from anon, authenticated;
