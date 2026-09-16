-- نسخة مُصغَّرة من قاعدة النظام القديم، لاختبار الترحيل على شيء يشبه المصدر.
--
/*
 * تحذير صريح: هذا المخطط **مُعاد بناؤه** من التدقيق في docs/system-analysis.md
 * لا من تفريغ حقيقي للإنتاج. أسماء الأعمدة قد تختلف عن الواقع.
 *
 * ولهذا لا يقرأ التحويل من `legacy` مباشرة بل من عروض `src` في
 * 01-source-adapter.sql: إن اختلف المخطط الحقيقي، يُعدَّل ملف المحوّل وحده
 * ويبقى منطق التحويل والتحقق كما هو. المواءمة مع التفريغ الحقيقي تتم في
 * بروفة اليوم −14.
 *
 * البيانات هنا مختارة لتغطي كل حالة صعبة لا لتكون واقعية:
 * delivered بالنسختين مع الصورة وبدونها، عميل يتيم، هاتف مكرر، ملف ناقص،
 * تحديات OTP فاشلة، مكتمل غير مدفوع، ونقد محصَّل بلا تسوية.
 */
drop schema if exists legacy cascade;
create schema legacy;

create table legacy.staff_profiles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null,
  email      text not null unique,
  full_name  text not null,
  role       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table legacy.properties (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  address    text,
  latitude   numeric,
  longitude  numeric,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table legacy.customers (
  id               uuid primary key default gen_random_uuid(),
  property_id      uuid references legacy.properties(id),
  qr_token         uuid not null unique,
  full_name        text,
  phone            text,
  floor_number     text,
  apartment_number text,
  profile_status   text not null default 'incomplete',
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

create table legacy.scan_events (
  id              uuid primary key default gen_random_uuid(),
  customer_id     uuid references legacy.customers(id),
  scan_session_id uuid not null,
  ip_hash         text,
  user_agent      text,
  result          text not null,
  created_at      timestamptz not null default now()
);

create table legacy.otp_challenges (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references legacy.customers(id),
  scan_event_id  uuid not null references legacy.scan_events(id),
  code_hash      text not null,
  phone          text not null,
  attempts       smallint not null default 0,
  status         text not null default 'pending',
  expires_at     timestamptz not null,
  verified_at    timestamptz,
  created_at     timestamptz not null default now()
);

-- workflow_version هو ما يميّز معنى delivered؛ ADR-010 يلغيه بعد الترحيل
create table legacy.orders (
  id                    uuid primary key default gen_random_uuid(),
  customer_id           uuid not null references legacy.customers(id),
  property_id           uuid not null references legacy.properties(id),
  status                text not null,
  workflow_version      smallint not null default 2,
  scan_event_id         uuid references legacy.scan_events(id),
  otp_challenge_id      uuid unique references legacy.otp_challenges(id),
  order_photo_path      text,
  pickup_photo_path     text,
  delivery_photo_path   text,
  pickup_confirmed_at   timestamptz,
  pickup_confirmed_by   uuid references legacy.staff_profiles(id),
  delivery_confirmed_at timestamptz,
  delivery_confirmed_by uuid references legacy.staff_profiles(id),
  invoice_number        text,
  invoice_amount        numeric(12,3),
  payment_status        text not null default 'unpaid',
  payment_method        text,
  thawani_session_id    text,
  paid_at               timestamptz,
  cancelled_at          timestamptz,
  cancel_reason         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table legacy.order_status_settings (
  status         text primary key,
  notify_enabled boolean not null default true,
  message        text not null
);

create table legacy.order_status_notifications (
  id         bigint generated always as identity primary key,
  order_id   uuid references legacy.orders(id),
  status     text not null,
  phone      text,
  message    text,
  state      text not null,
  error      text,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);

-- ── بيانات ────────────────────────────────────────────────────────────────
insert into legacy.staff_profiles (id, user_id, email, full_name, role, is_active) values
  ('11111111-0000-0000-0000-000000000001', gen_random_uuid(), 'owner@myduby.test',   'المالك',      'admin',    true),
  ('11111111-0000-0000-0000-000000000002', gen_random_uuid(), 'field@myduby.test',   'سالم الميداني', 'staff',   true),
  ('11111111-0000-0000-0000-000000000003', gen_random_uuid(), 'office@myduby.test',  'مريم المكتب',  'staff',    true),
  ('11111111-0000-0000-0000-000000000004', gen_random_uuid(), 'left@myduby.test',    'موظف سابق',    'staff',    false);

insert into legacy.properties (id, name, address, is_active) values
  ('22222222-0000-0000-0000-000000000001', 'برج الموج',   'الموج، مسقط', true),
  ('22222222-0000-0000-0000-000000000002', 'واحة السيفة', 'السيفة',      true),
  ('22222222-0000-0000-0000-000000000003', 'مبنى مغلق',   'الخوير',      false);

insert into legacy.customers
  (id, property_id, qr_token, full_name, phone, floor_number, apartment_number, profile_status, is_active) values
  ('33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001',
   '44444444-0000-0000-0000-000000000001', 'أحمد البلوشي', '+96891000001', '3', '302', 'complete', true),
  ('33333333-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001',
   '44444444-0000-0000-0000-000000000002', 'خالد الحارثي', '+96891000002', '5', '501', 'complete', true),
  ('33333333-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000002',
   '44444444-0000-0000-0000-000000000003', 'منى الكندية',  '+96891000003', '1', '102', 'complete', true),
  -- ملف ناقص: رمزه مطبوع وموزّع، فيُرحَّل كما هو (D2)
  ('33333333-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000002',
   '44444444-0000-0000-0000-000000000004', null, null, null, null, 'incomplete', true),
  -- عميل بلا عقار (D1)
  ('33333333-0000-0000-0000-000000000005', null,
   '44444444-0000-0000-0000-000000000005', 'يتيم بلا عقار', '+96891000005', '2', '201', 'complete', true),
  -- هاتف مكرر بين فعّالين: القيد الجديد فريد، فلا بد من قرار
  ('33333333-0000-0000-0000-000000000006', '22222222-0000-0000-0000-000000000001',
   '44444444-0000-0000-0000-000000000006', 'مكرر الهاتف', '+96891000001', '4', '401', 'complete', true);

insert into legacy.scan_events (id, customer_id, scan_session_id, result, created_at) values
  ('55555555-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001',
   gen_random_uuid(), 'order_created', now() - interval '20 days'),
  ('55555555-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000002',
   gen_random_uuid(), 'order_created', now() - interval '15 days'),
  ('55555555-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000003',
   gen_random_uuid(), 'otp_sent',       now() - interval '10 days'),
  ('55555555-0000-0000-0000-000000000004', null,
   gen_random_uuid(), 'invalid_token',  now() - interval '200 days'),
  ('55555555-0000-0000-0000-000000000005', '33333333-0000-0000-0000-000000000001',
   gen_random_uuid(), 'order_created',  now() - interval '5 days'),
  ('55555555-0000-0000-0000-000000000006', '33333333-0000-0000-0000-000000000002',
   gen_random_uuid(), 'order_created',  now() - interval '2 days');

insert into legacy.otp_challenges
  (id, customer_id, scan_event_id, code_hash, phone, attempts, status, expires_at, verified_at, created_at) values
  ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001',
   '55555555-0000-0000-0000-000000000001', 'hash1', '+96891000001', 1, 'verified',
   now() - interval '20 days', now() - interval '20 days', now() - interval '20 days'),
  ('66666666-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-000000000002', 'hash2', '+96891000002', 1, 'verified',
   now() - interval '15 days', now() - interval '15 days', now() - interval '15 days'),
  -- فاشلة وقديمة: تُستبعد (D3 + سياسة الاحتفاظ ٩٠ يومًا)
  ('66666666-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000003',
   '55555555-0000-0000-0000-000000000003', 'hash3', '+96891000003', 5, 'failed',
   now() - interval '200 days', null, now() - interval '200 days'),
  ('66666666-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000001',
   '55555555-0000-0000-0000-000000000005', 'hash4', '+96891000001', 1, 'verified',
   now() - interval '5 days', now() - interval '5 days', now() - interval '5 days'),
  ('66666666-0000-0000-0000-000000000005', '33333333-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-000000000006', 'hash5', '+96891000002', 1, 'verified',
   now() - interval '2 days', now() - interval '2 days', now() - interval '2 days');

insert into legacy.orders
  (id, customer_id, property_id, status, workflow_version, scan_event_id, otp_challenge_id,
   order_photo_path, pickup_photo_path, delivery_photo_path,
   pickup_confirmed_at, pickup_confirmed_by, delivery_confirmed_at, delivery_confirmed_by,
   invoice_number, invoice_amount, payment_status, payment_method, paid_at,
   cancelled_at, cancel_reason, created_at) values
  -- 1) delivered بالنسخة 1 → مكتمل (تسليم نهائي)
  ('77777777-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001',
   '22222222-0000-0000-0000-000000000001', 'delivered', 1,
   '55555555-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001',
   'orders/o1.jpg', 'pickups/p1.jpg', 'deliveries/d1.jpg',
   now() - interval '19 days', '11111111-0000-0000-0000-000000000002',
   now() - interval '18 days', '11111111-0000-0000-0000-000000000002',
   'INV-1001', 12.500, 'paid', 'cash_on_delivery', now() - interval '18 days',
   null, null, now() - interval '20 days'),
  -- 2) delivered بالنسخة 2 مع صورة تسليم → مكتمل
  ('77777777-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000002',
   '22222222-0000-0000-0000-000000000001', 'delivered', 2,
   '55555555-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002',
   'orders/o2.jpg', 'pickups/p2.jpg', 'deliveries/d2.jpg',
   now() - interval '14 days', '11111111-0000-0000-0000-000000000002',
   now() - interval '13 days', '11111111-0000-0000-0000-000000000002',
   'INV-1002', 8.000, 'paid', 'thawani', now() - interval '13 days',
   null, null, now() - interval '15 days'),
  -- 3) delivered بالنسخة 2 بلا صورة تسليم → خرج للتوصيل (لم يُسلَّم)
  ('77777777-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000001',
   '22222222-0000-0000-0000-000000000001', 'delivered', 2,
   '55555555-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000004',
   'orders/o3.jpg', 'pickups/p3.jpg', null,
   now() - interval '4 days', '11111111-0000-0000-0000-000000000002',
   null, null,
   'INV-1003', 6.250, 'unpaid', null, null,
   null, null, now() - interval '5 days'),
  -- 4) completed بالنسخة 1 → خرج للتوصيل (كان يعني «جاهز مع فاتورة»)
  ('77777777-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000003',
   '22222222-0000-0000-0000-000000000002', 'completed', 1,
   null, null,
   'orders/o4.jpg', 'pickups/p4.jpg', null,
   now() - interval '9 days', '11111111-0000-0000-0000-000000000002',
   null, null,
   'INV-1004', 15.750, 'unpaid', null, null,
   null, null, now() - interval '10 days'),
  -- 5) نشط
  ('77777777-0000-0000-0000-000000000005', '33333333-0000-0000-0000-000000000002',
   '22222222-0000-0000-0000-000000000001', 'processing', 2,
   '55555555-0000-0000-0000-000000000006', '66666666-0000-0000-0000-000000000005',
   'orders/o5.jpg', 'pickups/p5.jpg', null,
   now() - interval '1 day', '11111111-0000-0000-0000-000000000002',
   null, null, null, null, 'unpaid', null, null,
   null, null, now() - interval '2 days'),
  -- 6) ملغي بلا سبب مسجّل: القيد الجديد يشترط سببًا
  ('77777777-0000-0000-0000-000000000006', '33333333-0000-0000-0000-000000000003',
   '22222222-0000-0000-0000-000000000002', 'cancelled', 2,
   null, null, 'orders/o6.jpg', null, null,
   null, null, null, null, null, null, 'unpaid', null, null,
   now() - interval '30 days', null, now() - interval '31 days'),
  -- 7) شذوذ: delivered/completed لكنه غير مدفوع — القيد الجديد يرفض الاكتمال
  ('77777777-0000-0000-0000-000000000007', '33333333-0000-0000-0000-000000000001',
   '22222222-0000-0000-0000-000000000001', 'delivered', 1,
   null, null, 'orders/o7.jpg', 'pickups/p7.jpg', 'deliveries/d7.jpg',
   now() - interval '25 days', '11111111-0000-0000-0000-000000000002',
   now() - interval '24 days', '11111111-0000-0000-0000-000000000002',
   'INV-1007', 5.000, 'unpaid', null, null,
   null, null, now() - interval '26 days');

insert into legacy.order_status_settings (status, notify_enabled, message) values
  ('new',        false, 'تم استلام طلبكم'),
  ('confirmed',  true,  'تم تأكيد طلبكم'),
  ('picked_up',  true,  'تم استلام الملابس'),
  ('processing', true,  'طلبكم قيد التنفيذ'),
  ('ready',      true,  'طلبكم جاهز'),
  ('delivered',  true,  'طلبكم في الطريق إليكم'),
  ('completed',  true,  'تم تسليم طلبكم. شكرًا لثقتكم'),
  ('cancelled',  true,  'تم إلغاء طلبكم');

insert into legacy.order_status_notifications (order_id, status, phone, message, state, sent_at)
select o.id, o.status, c.phone, 'تحديث', 'sent', o.created_at
  from legacy.orders o join legacy.customers c on c.id = o.customer_id;
