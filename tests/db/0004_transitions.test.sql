-- مصفوفة انتقالات الطلب: كل الخانات الـ64 بقرار صريح.
begin;
select plan(71);

insert into properties (id, code, name)
values ('11111111-1111-1111-1111-111111111111', 'TSTA', 'برج الاختبار أ');
insert into customers (id, property_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 's@test.local');
insert into staff (id, user_id, full_name, role)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'سالم', 'operator');

-- الانتقالات المسموحة الاثنا عشر، مطابقة لوثيقة التدفقات
create temp table expected_allowed (from_s order_status, to_s order_status);
insert into expected_allowed values
  ('new','confirmed'), ('confirmed','picked_up'), ('picked_up','processing'),
  ('processing','ready'), ('ready','out_for_delivery'), ('out_for_delivery','completed'),
  ('new','cancelled'), ('confirmed','cancelled'), ('picked_up','cancelled'),
  ('processing','cancelled'), ('ready','cancelled'), ('out_for_delivery','cancelled');

-- 64 اختبارًا: كل خانة في المصفوفة
select is(
  order_transition_allowed(f, t),
  exists (select 1 from expected_allowed e where e.from_s = f and e.to_s = t),
  format('%s ← %s', f, t)
)
from unnest(enum_range(null::order_status)) f,
     unnest(enum_range(null::order_status)) t;

-- ── الحارس يعمل فعليًا على الجدول لا في الدالة وحدها ──────────────────────
insert into orders (id, customer_id, property_id)
values ('55555555-5555-5555-5555-555555555555',
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111');

select throws_ok(
  $$ update orders set status = 'picked_up' where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'الحارس يرفض القفز من «جديد» إلى «تم الاستلام»'
);

select lives_ok(
  $$ update orders set status = 'confirmed' where id = '55555555-5555-5555-5555-555555555555' $$,
  'الحارس يقبل الانتقال المسموح'
);

-- سجل الحالات يُكتب عند كل انتقال، من المحفّز لا من كود التطبيق
select is(
  (select count(*)::int from order_status_history
    where order_id = '55555555-5555-5555-5555-555555555555'),
  2,
  'سجل الحالات يُكتب تلقائيًا عند الانتقال'
);

select is(
  (select from_status from order_status_history
    where order_id = '55555555-5555-5555-5555-555555555555' and to_status = 'confirmed'),
  'new'::order_status,
  'السجل يحفظ الحالة السابقة'
);

-- ── القفل النهائي ─────────────────────────────────────────────────────────
update orders
   set payment_status = 'paid', payment_method = 'cash_on_delivery', paid_at = now(),
       paid_recorded_by = '44444444-4444-4444-4444-444444444444',
       pickup_confirmed_at = now(), pickup_confirmed_by = '44444444-4444-4444-4444-444444444444',
       delivery_confirmed_at = now(), delivery_confirmed_by = '44444444-4444-4444-4444-444444444444',
       invoice_number = 'INV-9', invoice_amount = 5.000, invoiced_at = now()
 where id = '55555555-5555-5555-5555-555555555555';

update orders set status = 'picked_up'  where id = '55555555-5555-5555-5555-555555555555';
update orders set status = 'processing' where id = '55555555-5555-5555-5555-555555555555';
update orders set status = 'ready'      where id = '55555555-5555-5555-5555-555555555555';
update orders set status = 'out_for_delivery' where id = '55555555-5555-5555-5555-555555555555';
update orders set status = 'completed'  where id = '55555555-5555-5555-5555-555555555555';

select is(
  (select status from orders where id = '55555555-5555-5555-5555-555555555555'),
  'completed'::order_status,
  'المسار الكامل من «جديد» إلى «مكتمل» يعمل'
);

select throws_ok(
  $$ update orders set status = 'cancelled' where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'الحالة النهائية مقفلة: لا إلغاء بعد الاكتمال'
);

-- القفل يشمل كل الحقول لا الحالة وحدها
select throws_ok(
  $$ update orders set invoice_amount = 99.000 where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'الحالة النهائية تقفل كل حقول الطلب'
);

select * from finish();
rollback;
