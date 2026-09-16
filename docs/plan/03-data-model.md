# 03 — نموذج البيانات

PostgreSQL 15. كل الجداول في مخطط `public` مع RLS مفعّل، عدا جداول التدقيق
والطوابير في مخطط `private` بلا وصول من الواجهة إطلاقًا.

---

## 1. الأنواع المعدودة

```sql
create type staff_role      as enum ('operator', 'manager', 'admin');
create type profile_status  as enum ('incomplete', 'complete');

create type order_status as enum (
  'new',              -- جديد
  'confirmed',        -- مؤكد
  'picked_up',        -- تم الاستلام   (QR + صورة في الموقع)
  'processing',       -- قيد التنفيذ
  'ready',            -- جاهز
  'out_for_delivery', -- خرج للتوصيل   (فاتورة + رابط دفع)
  'completed',        -- مكتمل         (دفع + QR + صورة تسليم) — نهائية
  'cancelled'         -- ملغي
);

create type payment_status  as enum ('unpaid', 'paid', 'refunded');
create type payment_method  as enum ('thawani', 'cash_on_delivery', 'manual');
create type photo_kind      as enum ('intake', 'pickup', 'delivery');
create type otp_state       as enum ('pending','sent','verified','failed','blocked','expired','superseded');
create type outbox_state    as enum ('pending','sending','sent','failed','skipped','dead');
```

> **تصحيح مقصود**: `delivered` حُذفت. في النظام الحالي كانت تُستخدم قبل التسليم
> الفعلي، وهو التباس أنتج طلبات عالقة. بديلها `out_for_delivery` بمعنى صريح،
> و`completed` هي التسليم المؤكد بالـQR والصورة.

---

## 2. الجداول

### 2.1 `staff` — الموظفون

```sql
create table staff (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete restrict,
  full_name   text not null check (length(btrim(full_name)) between 2 and 120),
  phone       text check (phone ~ '^\+968[0-9]{8}$'),
  role        staff_role not null default 'operator',
  is_active   boolean not null default true,
  created_by  uuid references staff(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index staff_role_active_idx on staff(role) where deleted_at is null and is_active;
```

**دالة الدور** — أساس كل سياسات RLS:

```sql
create or replace function auth_role() returns staff_role
language sql stable security definer set search_path = public as $$
  select role from staff
   where user_id = auth.uid() and is_active and deleted_at is null
$$;

create or replace function auth_staff_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from staff
   where user_id = auth.uid() and is_active and deleted_at is null
$$;
```

الموظف المعطَّل تعيد له الدالة `null` ← كل السياسات ترفضه. تعطيل الحساب يصبح
فوريًا وفعّالًا بلا اعتماد على الواجهة.

### 2.2 `properties` — العقارات

```sql
create table properties (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z0-9-]{2,16}$'),
  name        text not null check (length(btrim(name)) between 2 and 120),
  address     text,
  latitude    numeric(9,6)  check (latitude  between -90  and 90),
  longitude   numeric(9,6)  check (longitude between -180 and 180),
  is_active   boolean not null default true,
  created_by  uuid references staff(id),
  updated_by  uuid references staff(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  constraint properties_coords_together
    check ((latitude is null) = (longitude is null))
);

create index properties_active_idx on properties(is_active) where deleted_at is null;
```

`code` مضاف جديدًا: معرّف قصير ثابت للطباعة والتقارير، لا يتغير بتغير الاسم.

### 2.3 `customers` — العملاء

```sql
create table customers (
  id                  uuid primary key default gen_random_uuid(),
  customer_no         bigint generated always as identity,
  property_id         uuid not null references properties(id) on delete restrict,
  full_name           text,
  phone               text check (phone ~ '^\+968[0-9]{8}$'),
  floor_number        text check (length(btrim(floor_number))    between 1 and 10),
  apartment_number    text check (length(btrim(apartment_number)) between 1 and 10),
  notes               text,
  profile_status      profile_status not null default 'incomplete',
  profile_completed_at timestamptz,
  is_active           boolean not null default true,
  created_by          uuid references staff(id),
  updated_by          uuid references staff(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,

  -- الملف المكتمل يعني: كل الحقول موجودة فعلًا
  constraint customers_complete_requires_fields check (
    profile_status = 'incomplete' or (
      full_name is not null and phone is not null
      and floor_number is not null and apartment_number is not null
      and profile_completed_at is not null
    )
  )
);

create unique index customers_no_idx on customers(customer_no);
create unique index customers_phone_active_idx
  on customers(phone) where phone is not null and is_active and deleted_at is null;
create index customers_property_idx on customers(property_id) where deleted_at is null;
create index customers_status_idx   on customers(profile_status, is_active) where deleted_at is null;
```

`property_id` **NOT NULL** — القاعدة مفروضة في المخطط لا في الخدمة.
الفهرس الفريد الجزئي يمنع تكرار الهاتف بين العملاء الفعّالين ويسمح بإعادة
استخدامه بعد تعطيل عميل.

### 2.4 `customer_qr_tokens` — رموز QR وتاريخها

```sql
create table customer_qr_tokens (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  token       uuid not null unique default gen_random_uuid(),
  issued_at   timestamptz not null default now(),
  issued_by   uuid references staff(id),
  revoked_at  timestamptz,
  revoked_by  uuid references staff(id),
  revoke_reason text
);

-- رمز فعّال واحد لكل عميل
create unique index customer_qr_active_idx
  on customer_qr_tokens(customer_id) where revoked_at is null;
create index customer_qr_token_lookup_idx
  on customer_qr_tokens(token) where revoked_at is null;
```

**تحسين على النظام الحالي**: الرمز كان حقلًا في `customers` يُستبدل عند إعادة
الإصدار، فيضيع تاريخه. هنا كل رمز سجل مستقل، فنعرف متى أُصدر ومن أصدره ومتى
أُبطل ولماذا — ونستطيع تشخيص «رمز قديم» بدل رفضه بصمت.

### 2.5 `scan_events` — المسحات

```sql
create table scan_events (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid references customers(id) on delete set null,
  qr_token_id       uuid references customer_qr_tokens(id) on delete set null,
  scan_session_id   uuid not null unique,
  ip_hash           text,
  user_agent        text,
  result            text not null,
  scanned_at        timestamptz not null default now(),
  otp_requested_at  timestamptz,
  verified_at       timestamptz,
  order_submitted_at timestamptz,
  request_id        text
);

create index scan_events_customer_idx on scan_events(customer_id, scanned_at desc);
create index scan_events_result_idx   on scan_events(result, scanned_at desc);
```

القيم الممكنة لـ`result`: `scanned`, `profile_required`, `otp_requested`,
`otp_sent`, `otp_failed`, `verified`, `order_submitted`, `invalid_qr`,
`revoked_qr`, `inactive_customer`, `blocked`, `expired`, `abandoned`.

### 2.6 `otp_challenges` — تحديات التحقق

```sql
create table otp_challenges (
  id              uuid primary key default gen_random_uuid(),
  customer_id     uuid not null references customers(id) on delete cascade,
  scan_event_id   uuid not null references scan_events(id) on delete cascade,
  code_hash       text not null,            -- HMAC-SHA256(qr_token|scan_session|code, pepper)
  phone_snapshot  text not null,
  state           otp_state not null default 'pending',
  attempts        smallint not null default 0 check (attempts between 0 and 10),
  max_attempts    smallint not null default 5,
  expires_at      timestamptz not null,
  verified_at     timestamptz,
  created_at      timestamptz not null default now()
);

create index otp_customer_idx on otp_challenges(customer_id, created_at desc);
create index otp_expiry_idx   on otp_challenges(expires_at) where state in ('pending','sent');
```

`code_hash` فقط — الرمز الصريح لا يوجد في قاعدة البيانات ولا في السجلات ولا في
الاستثناءات. الـpepper في أسرار Edge Functions.

### 2.7 `order_submissions` — رموز الإرسال

```sql
create table order_submissions (
  id                uuid primary key default gen_random_uuid(),
  otp_challenge_id  uuid not null unique references otp_challenges(id) on delete cascade,
  customer_id       uuid not null references customers(id) on delete cascade,
  token_hash        text not null unique,
  expires_at        timestamptz not null,
  consumed_at       timestamptz,
  order_id          uuid,
  created_at        timestamptz not null default now()
);
```

بعد نجاح OTP يُصدر رمز إرسال صالح 15 دقيقة يُستهلك مرة واحدة. الفهرس الفريد على
`otp_challenge_id` هو ما يمنع ازدواج الطلب من نفس التحقق.

### 2.8 `orders` — الطلبات

```sql
create table orders (
  id                uuid primary key default gen_random_uuid(),
  order_no          bigint generated always as identity,
  customer_id       uuid not null references customers(id) on delete restrict,
  property_id       uuid not null references properties(id) on delete restrict,
  scan_event_id     uuid unique references scan_events(id) on delete set null,
  submission_id     uuid unique references order_submissions(id) on delete set null,

  status            order_status not null default 'new',
  status_changed_at timestamptz not null default now(),

  -- الاستلام الميداني
  pickup_confirmed_at timestamptz,
  pickup_confirmed_by uuid references staff(id),

  -- التسليم الميداني
  delivery_confirmed_at timestamptz,
  delivery_confirmed_by uuid references staff(id),

  -- الفوترة
  invoice_number    text,
  invoice_amount    numeric(12,3) check (invoice_amount is null or invoice_amount >= 0.100),
  invoiced_at       timestamptz,
  invoiced_by       uuid references staff(id),

  -- الدفع
  payment_status    payment_status not null default 'unpaid',
  payment_method    payment_method,
  paid_at           timestamptz,
  paid_recorded_by  uuid references staff(id),

  -- الإلغاء
  cancelled_at      timestamptz,
  cancelled_by      uuid references staff(id),
  cancel_reason     text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
```

#### القيود — قواعد العمل التي لا تُخرق

```sql
-- رقم فاتورة فريد (كان مفقودًا في النظام الحالي رغم أن الكود يتوقعه)
create unique index orders_invoice_no_idx
  on orders(invoice_number) where invoice_number is not null;

alter table orders add constraint orders_invoice_complete check (
  (invoice_number is null and invoice_amount is null and invoiced_at is null)
  or
  (invoice_number is not null and invoice_amount is not null and invoiced_at is not null)
);

-- لا خروج للتوصيل بلا فاتورة
alter table orders add constraint orders_out_for_delivery_needs_invoice check (
  status <> 'out_for_delivery' or invoice_number is not null
);

-- الدفع متسق: paid ⇔ طريقة ووقت
alter table orders add constraint orders_payment_consistent check (
  (payment_status = 'unpaid' and payment_method is null and paid_at is null)
  or
  (payment_status in ('paid','refunded') and payment_method is not null and paid_at is not null)
);

-- الاكتمال يتطلب: دفعًا + تأكيد تسليم
alter table orders add constraint orders_completed_requires_payment check (
  status <> 'completed' or payment_status = 'paid'
);

alter table orders add constraint orders_completed_requires_delivery check (
  status <> 'completed'
  or (delivery_confirmed_at is not null and delivery_confirmed_by is not null)
);

-- الاستلام يتطلب تأكيدًا ميدانيًا
alter table orders add constraint orders_picked_up_requires_confirmation check (
  status = 'new' or status = 'confirmed' or status = 'cancelled'
  or (pickup_confirmed_at is not null and pickup_confirmed_by is not null)
);

-- الإلغاء يتطلب سببًا
alter table orders add constraint orders_cancel_requires_reason check (
  status <> 'cancelled'
  or (cancelled_at is not null and cancelled_by is not null
      and length(btrim(coalesce(cancel_reason,''))) >= 3)
);
```

> **درس مطبَّق**: النظام الحالي عطّله مرتين تعبيرٌ منتظم داخل قيد لم يطابق أي
> مسار صحيح. لذلك **لا تعبيرات منتظمة على المسارات في القيود هنا** — التحقق من
> الصور يتم بمفتاح أجنبي إلى `order_photos`، وهو فحص بنيوي لا نصّي.

#### الفهارس

```sql
create unique index orders_no_idx on orders(order_no);
create index orders_active_idx   on orders(property_id, status, created_at desc)
  where status not in ('completed','cancelled');
create index orders_customer_idx on orders(customer_id, created_at desc);
create index orders_payment_idx  on orders(payment_status, invoiced_at)
  where payment_status = 'unpaid' and invoice_number is not null;
create index orders_status_idx   on orders(status, status_changed_at desc);
```

الفهرس الجزئي الأول يخدم الاستعلام الأكثر تكرارًا: طلبات نشطة مجمّعة حسب العقار.

### 2.9 `order_photos` — صور الطلبات

```sql
create table order_photos (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references orders(id) on delete cascade,
  kind         photo_kind not null,
  storage_path text not null unique,
  byte_size    integer not null check (byte_size between 1 and 2097152),
  sha256       text not null,
  taken_by     uuid references staff(id),          -- null لصورة العميل
  taken_at     timestamptz not null default now(),
  latitude     numeric(9,6),
  longitude    numeric(9,6)
);

-- صورة واحدة من كل نوع لكل طلب
create unique index order_photos_kind_idx on order_photos(order_id, kind);
```

`sha256` يكشف إعادة استخدام صورة قديمة لتزييف حضور ميداني.
`latitude/longitude` اختياريان لتوثيق موقع الالتقاط عند توفر الإذن.

### 2.10 `order_status_history` — سجل الحالات (غير قابل للتعديل)

```sql
create table order_status_history (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references orders(id) on delete cascade,
  from_status order_status,
  to_status   order_status not null,
  changed_by  uuid references staff(id),
  changed_at  timestamptz not null default now(),
  reason      text,
  request_id  text,
  context     jsonb not null default '{}'::jsonb
);

create index osh_order_idx on order_status_history(order_id, changed_at);

-- منع التعديل والحذف على مستوى قاعدة البيانات
create rule osh_no_update as on update to order_status_history do instead nothing;
create rule osh_no_delete as on delete to order_status_history do instead nothing;
```

يُكتب بمحفّز على `orders`، لا من كود التطبيق — فيستحيل تغيير حالة بلا سجل.

### 2.11 `payments` و `payment_events`

```sql
create table payments (
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

create index payments_order_idx on payments(order_id, created_at desc);

create table payment_events (
  id                bigint generated always as identity primary key,
  payment_id        uuid references payments(id) on delete cascade,
  order_id          uuid not null references orders(id) on delete cascade,
  event_type        text not null,      -- session_created | webhook | polled | manual_cash | reversed
  old_status        text,
  new_status        text,
  provider_ref      text,
  safe_payload      jsonb not null default '{}'::jsonb,
  created_by        uuid references staff(id),
  created_at        timestamptz not null default now()
);

create index payment_events_order_idx on payment_events(order_id, created_at desc);
```

`provider_session_id` و`return_token_hash` و`idempotency_key` كلها فريدة —
الثلاثة كانت مفقودة في النظام الحالي. `safe_payload` يحفظ الحقول غير الحساسة
فقط من استجابة المزود.

### 2.12 `notification_outbox` — طابور الإشعارات

```sql
create table private.notification_outbox (
  id              bigint generated always as identity primary key,
  kind            text not null,           -- otp | status_update
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

create index outbox_due_idx on private.notification_outbox(next_attempt_at)
  where state in ('pending','failed');
```

`params` يحوي النص النهائي فقط — **لا يحوي رمز OTP** إطلاقًا (يُمرَّر مباشرة
دون المرور بالطابور؛ التفصيل في [08-integrations.md](08-integrations.md)).

### 2.13 `order_status_settings` — إعدادات الإشعارات

```sql
create table order_status_settings (
  status               order_status primary key,
  label_ar             text not null,
  sort_order           smallint not null,
  notify_enabled       boolean not null default true,
  notification_message text not null,
  template_name        text not null default 'ar_template',
  updated_by           uuid references staff(id),
  updated_at           timestamptz not null default now()
);
```

### 2.14 `audit_logs` — سجل التدقيق

```sql
create table private.audit_logs (
  id          bigint generated always as identity primary key,
  actor_id    uuid,
  actor_role  staff_role,
  action      text not null,
  entity      text not null,
  entity_id   uuid,
  before      jsonb,
  after       jsonb,
  reason      text,
  request_id  text,
  ip_hash     text,
  created_at  timestamptz not null default now()
);

create index audit_entity_idx on private.audit_logs(entity, entity_id, created_at desc);
create index audit_actor_idx  on private.audit_logs(actor_id, created_at desc);
```

يُكتب بمحفّزات على الجداول الحساسة. مخطط `private` = لا وصول من الواجهة أبدًا؛
القراءة تمر عبر دالة مقيّدة بـ`admin`.

### 2.15 `app_settings`

```sql
create table app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_by  uuid references staff(id),
  updated_at  timestamptz not null default now()
);
```

قيم مثل `otp.ttl_seconds`, `otp.max_per_hour`, `photos.retention_days`,
`orders.stale_alert_hours`.

---

## 3. سياسات RLS

القاعدة العامة: **الواجهة تقرأ، ولا تكتب**. كل الكتابة تمر عبر دوال
`SECURITY DEFINER` تُستدعى من Edge Functions بـ`service_role`.

هذا يحل جذريًا التعارض الحرج في النظام الحالي (دور `authenticated` بصلاحية قراءة
فقط بينما الواجهة تحاول الكتابة).

```sql
alter table staff              enable row level security;
alter table properties         enable row level security;
alter table customers          enable row level security;
alter table customer_qr_tokens enable row level security;
alter table scan_events        enable row level security;
alter table otp_challenges     enable row level security;
alter table order_submissions  enable row level security;
alter table orders             enable row level security;
alter table order_photos       enable row level security;
alter table order_status_history enable row level security;
alter table payments           enable row level security;
alter table payment_events     enable row level security;
alter table order_status_settings enable row level security;
alter table app_settings       enable row level security;
```

### مصفوفة السياسات

| الجدول | `anon` | `authenticated` | ملاحظات |
|---|---|---|---|
| `staff` | ✗ | قراءة سجله + قراءة الكل لـ`admin` | |
| `properties` | ✗ | قراءة | الكتابة عبر دوال |
| `customers` | ✗ | قراءة | |
| `customer_qr_tokens` | ✗ | قراءة الفعّال فقط | |
| `scan_events` | ✗ | قراءة | |
| `otp_challenges` | ✗ | **✗** | لا قراءة إطلاقًا — حتى للموظف |
| `order_submissions` | ✗ | **✗** | |
| `orders` | ✗ | قراءة | |
| `order_photos` | ✗ | قراءة البيانات الوصفية | الملف عبر رابط موقّع |
| `order_status_history` | ✗ | قراءة | لا كتابة لأحد |
| `payments` | ✗ | قراءة | |
| `payment_events` | ✗ | قراءة لـ`manager`+ | |
| `order_status_settings` | ✗ | قراءة | الكتابة لـ`admin` عبر دالة |
| `app_settings` | ✗ | قراءة لـ`admin` | |
| `private.*` | ✗ | ✗ | لا وصول إطلاقًا |

نموذج سياسة:

```sql
create policy orders_read_staff on orders
  for select to authenticated
  using (auth_role() is not null);

-- لا سياسة insert/update/delete على orders لأي دور
```

غياب سياسة الكتابة مقصود: `service_role` يتجاوز RLS، وهو الوحيد الذي يكتب.

### تخزين الصور

```sql
insert into storage.buckets (id, name, public) values ('order-photos','order-photos',false);
-- لا سياسات storage.objects لـ anon أو authenticated
-- القراءة حصرًا عبر رابط موقّع يصدره staff-orders بعد فحص الصلاحية
```

---

## 4. الدوال الذرّية

التوقيعات الكاملة في [05-api-contracts.md](05-api-contracts.md). القائمة:

| الدالة | الغرض |
|---|---|
| `fn_create_customer_with_qr(property_id, actor)` | إنشاء عميل + رمز في معاملة واحدة |
| `fn_reissue_qr(customer_id, actor, reason)` | إبطال الرمز الحالي وإصدار بديل |
| `fn_complete_profile(scan_session, name, phone, floor, apt)` | استكمال الملف — يتجاهل أي `property_id` وارد |
| `fn_issue_otp(scan_session)` | إصدار تحدٍّ جديد وإبطال السابق |
| `fn_verify_otp(scan_session, code_hash)` | تحقق + إصدار رمز إرسال |
| `fn_submit_order(submission_token_hash, photo_path, size, sha256)` | إنشاء الطلب وربط الصورة |
| `fn_advance_status(order_id, expected_from, actor)` | انتقال يدوي مع فحص تفاؤلي للحالة |
| `fn_confirm_field_step(order_id, step, qr_token, photo_path, size, sha256, actor)` | **الاستلام والتسليم** — ذرّية كاملة |
| `fn_cancel_order(order_id, reason, actor)` | إلغاء مع سبب |
| `fn_create_invoice(order_id, number, amount, actor)` | فاتورة + انتقال إلى `out_for_delivery` |
| `fn_record_cash_payment(order_id, actor)` | دفع نقدي — `manager`+ |
| `fn_apply_payment_webhook(session_id, provider_status, payload)` | تأكيد الدفع من المزود |
| `fn_reverse_payment(order_id, reason, actor)` | إلغاء دفع — `admin` فقط |

كل دالة تتحقق من دور المستدعي داخلها. الصلاحية لا تُفترض من مصدر الاستدعاء.

---

## 5. المحفّزات

| المحفّز | الجدول | الوظيفة |
|---|---|---|
| `trg_orders_status_history` | `orders` | كتابة سجل عند تغيّر `status` |
| `trg_orders_guard_transition` | `orders` | رفض أي انتقال غير مسموح في مصفوفة الحالات |
| `trg_orders_final_lock` | `orders` | رفض أي تعديل على طلب `completed` عدا `updated_at` |
| `trg_orders_notify_outbox` | `orders` | إدراج إشعار في Outbox عند تغيّر الحالة إن كان مفعّلًا |
| `trg_audit_*` | الجداول الحساسة | كتابة `private.audit_logs` |
| `trg_touch_updated_at` | الجميع | تحديث `updated_at` |

**ملاحظة**: `trg_orders_notify_outbox` يدرج في الطابور داخل نفس المعاملة. هذا
يضمن أن تغيّر الحالة وجدولة الإشعار يقعان معًا أو لا يقعان — ويحل المشكلة
العالية «تحديث الحالة والإشعار والتدقيق ليست معاملة واحدة». الإرسال الفعلي
خارج المعاملة، فلا يُرجع فشلُ واتساب الحالةَ.

---

## 6. الاحتفاظ بالبيانات

| البيانات | المدة | الإجراء |
|---|---|---|
| صور الطلبات | 180 يومًا (قابلة للضبط) | حذف من Storage، يبقى سجل البيانات الوصفية |
| `otp_challenges` | 90 يومًا | حذف |
| `scan_events` غير المكتملة | 180 يومًا | حذف |
| الطلبات والفواتير والمدفوعات | 7 سنوات | احتفاظ (متطلب محاسبي) |
| `order_status_history` | عمر الطلب | احتفاظ |
| `audit_logs` | سنتان | أرشفة ثم حذف |

تُنفَّذ بمهمة `pg_cron` يومية، مع سجل لكل دورة حذف.
