-- 0007 — الطلبات وصورها وسجل حالاتها وإعدادات إشعاراتها.

create table if not exists orders (
  id                uuid primary key default gen_random_uuid(),
  order_no          bigint generated always as identity,
  customer_id       uuid not null references customers(id) on delete restrict,
  property_id       uuid not null references properties(id) on delete restrict,
  scan_event_id     uuid unique references scan_events(id) on delete set null,
  submission_id     uuid unique references order_submissions(id) on delete set null,

  status            order_status not null default 'new',
  status_changed_at timestamptz not null default now(),

  -- الاستلام الميداني
  pickup_confirmed_at   timestamptz,
  pickup_confirmed_by   uuid references staff(id),

  -- التسليم الميداني
  delivery_confirmed_at timestamptz,
  delivery_confirmed_by uuid references staff(id),

  -- الفوترة
  invoice_number  text,
  invoice_amount  numeric(12,3) check (invoice_amount is null or invoice_amount >= 0.100),
  invoiced_at     timestamptz,
  invoiced_by     uuid references staff(id),

  -- الدفع
  payment_status   payment_status not null default 'unpaid',
  payment_method   payment_method,
  paid_at          timestamptz,
  paid_recorded_by uuid references staff(id),

  -- الإلغاء
  cancelled_at  timestamptz,
  cancelled_by  uuid references staff(id),
  cancel_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ── القيود: قواعد العمل التي لا تُخرق ─────────────────────────────────────
-- الكود كان يتوقع خطأ التكرار 23505 بينما القيد مفقود في النظام السابق
create unique index if not exists orders_invoice_no_idx
  on orders(invoice_number) where invoice_number is not null;

alter table orders drop constraint if exists orders_invoice_complete;
alter table orders add constraint orders_invoice_complete check (
  (invoice_number is null and invoice_amount is null and invoiced_at is null)
  or (invoice_number is not null and invoice_amount is not null and invoiced_at is not null)
);

alter table orders drop constraint if exists orders_out_for_delivery_needs_invoice;
alter table orders add constraint orders_out_for_delivery_needs_invoice check (
  status <> 'out_for_delivery' or invoice_number is not null
);

alter table orders drop constraint if exists orders_payment_consistent;
alter table orders add constraint orders_payment_consistent check (
  (payment_status = 'unpaid' and payment_method is null and paid_at is null)
  or (payment_status in ('paid', 'refunded') and payment_method is not null and paid_at is not null)
);

alter table orders drop constraint if exists orders_completed_requires_payment;
alter table orders add constraint orders_completed_requires_payment check (
  status <> 'completed' or payment_status = 'paid'
);

alter table orders drop constraint if exists orders_completed_requires_delivery;
alter table orders add constraint orders_completed_requires_delivery check (
  status <> 'completed'
  or (delivery_confirmed_at is not null and delivery_confirmed_by is not null)
);

alter table orders drop constraint if exists orders_picked_up_requires_confirmation;
alter table orders add constraint orders_picked_up_requires_confirmation check (
  status in ('new', 'confirmed', 'cancelled')
  or (pickup_confirmed_at is not null and pickup_confirmed_by is not null)
);

alter table orders drop constraint if exists orders_cancel_requires_reason;
alter table orders add constraint orders_cancel_requires_reason check (
  status <> 'cancelled'
  or (cancelled_at is not null and cancelled_by is not null
      and length(btrim(coalesce(cancel_reason, ''))) >= 3)
);

-- ── الفهارس ───────────────────────────────────────────────────────────────
create unique index if not exists orders_no_idx on orders(order_no);

-- يخدم الاستعلام الأكثر تكرارًا: طلبات نشطة مجمّعة حسب العقار
create index if not exists orders_active_idx
  on orders(property_id, status, created_at desc)
  where status not in ('completed', 'cancelled');

create index if not exists orders_customer_idx on orders(customer_id, created_at desc);
create index if not exists orders_payment_idx
  on orders(payment_status, invoiced_at)
  where payment_status = 'unpaid' and invoice_number is not null;
create index if not exists orders_status_idx on orders(status, status_changed_at desc);

create trigger trg_orders_touch
  before update on orders
  for each row execute function touch_updated_at();

-- ── صور الطلبات ───────────────────────────────────────────────────────────
/*
 * لا تعبير منتظم على مسار الصورة في أي قيد. في النظام السابق عطّل التسليمَ
 * مرتين نمطٌ لم يطابق أي مسار صحيح. التحقق هنا بنيوي بمفتاح أجنبي، لا نصّي.
 */
create table if not exists order_photos (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references orders(id) on delete cascade,
  kind         photo_kind not null,
  storage_path text not null unique,
  byte_size    integer not null check (byte_size between 1 and 2097152),
  sha256       text not null,
  taken_by     uuid references staff(id),   -- null لصورة العميل
  taken_at     timestamptz not null default now(),
  latitude     numeric(9,6),
  longitude    numeric(9,6)
);

-- صورة واحدة من كل نوع لكل طلب
create unique index if not exists order_photos_kind_idx on order_photos(order_id, kind);

-- بصمة فريدة: تكشف إعادة استخدام صورة قديمة لتزييف حضور ميداني
create unique index if not exists order_photos_sha_idx on order_photos(sha256);

-- ── سجل الحالات: غير قابل للتعديل ────────────────────────────────────────
create table if not exists order_status_history (
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

create index if not exists osh_order_idx on order_status_history(order_id, changed_at);

-- يُكتب بمحفّز على orders لا من كود التطبيق، فيستحيل تغيير حالة بلا سجل
create or replace rule osh_no_update as on update to order_status_history do instead nothing;
create or replace rule osh_no_delete as on delete to order_status_history do instead nothing;

-- ── إعدادات إشعارات الحالات ───────────────────────────────────────────────
create table if not exists order_status_settings (
  status               order_status primary key,
  label_ar             text not null,
  sort_order           smallint not null,
  notify_enabled       boolean not null default true,
  notification_message text not null,
  template_name        text not null default 'ar_template',
  updated_by           uuid references staff(id),
  updated_at           timestamptz not null default now()
);

create trigger trg_status_settings_touch
  before update on order_status_settings
  for each row execute function touch_updated_at();

insert into order_status_settings (status, label_ar, sort_order, notify_enabled, notification_message) values
  ('new',              'جديد',          1, false, 'تم استلام طلبكم وسنؤكده قريبًا.'),
  ('confirmed',        'مؤكد',          2, true,  'لقد تم تأكيد طلبكم.'),
  ('picked_up',        'تم الاستلام',    3, true,  'تم استلام طلبكم من موقعكم.'),
  ('processing',       'قيد التنفيذ',    4, true,  'طلبكم قيد التنفيذ الآن.'),
  ('ready',            'جاهز',          5, true,  'طلبكم جاهز.'),
  ('out_for_delivery', 'خرج للتوصيل',   6, true,  'طلبكم في الطريق إليكم.'),
  ('completed',        'مكتمل',         7, true,  'تم تسليم طلبكم. شكرًا لثقتكم.'),
  ('cancelled',        'ملغي',          8, true,  'تم إلغاء طلبكم.')
on conflict (status) do nothing;
