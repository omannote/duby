-- القيود: لكل قيد اختباران — يرفض الخطأ ويقبل الصحيح.
-- قيد بلا اختبار لا يُدمج.
begin;
select plan(26);

-- بيانات أساس
insert into properties (id, code, name)
values ('11111111-1111-1111-1111-111111111111', 'TSTA', 'برج الاختبار أ');

insert into customers (id, property_id)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 's@test.local');
insert into staff (id, user_id, full_name, role)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'سالم', 'courier');

insert into orders (id, customer_id, property_id)
values ('55555555-5555-5555-5555-555555555555',
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111');

-- ── customers_complete_requires_fields ────────────────────────────────────
select throws_ok(
  $$ update customers set profile_status = 'complete'
      where id = '22222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'يرفض «مكتمل» بحقول ناقصة'
);

select lives_ok(
  $$ update customers set full_name = 'أحمد', phone = '+96891234567',
            floor_number = '3', apartment_number = '12',
            profile_completed_at = now(), profile_status = 'complete'
      where id = '22222222-2222-2222-2222-222222222222' $$,
  'يقبل «مكتمل» بكل الحقول'
);

-- ── customers_phone_active_idx ────────────────────────────────────────────
select throws_ok(
  $$ insert into customers (property_id, full_name, phone, floor_number, apartment_number,
                            profile_status, profile_completed_at)
     values ('11111111-1111-1111-1111-111111111111', 'مكرر', '+96891234567', '1', '1',
             'complete', now()) $$,
  '23505', null, 'يرفض تكرار الهاتف بين العملاء الفعّالين'
);

select lives_ok(
  $$ with disabled as (
       update customers set is_active = false
        where id = '22222222-2222-2222-2222-222222222222' returning 1
     )
     insert into customers (property_id, full_name, phone, floor_number, apartment_number,
                            profile_status, profile_completed_at)
     select '11111111-1111-1111-1111-111111111111', 'بديل', '+96891234567', '1', '1',
            'complete', now() from disabled $$,
  'يسمح بإعادة استخدام الهاتف بعد تعطيل صاحبه'
);

delete from customers where full_name = 'بديل';
update customers set is_active = true where id = '22222222-2222-2222-2222-222222222222';

-- ── customer_qr_active_idx ────────────────────────────────────────────────
insert into customer_qr_tokens (customer_id)
values ('22222222-2222-2222-2222-222222222222');

select throws_ok(
  $$ insert into customer_qr_tokens (customer_id)
     values ('22222222-2222-2222-2222-222222222222') $$,
  '23505', null, 'يرفض رمزين فعّالين لعميل واحد'
);

select lives_ok(
  $$ with revoked as (
       update customer_qr_tokens
          set revoked_at = now(),
              revoked_by = '44444444-4444-4444-4444-444444444444',
              revoke_reason = 'فقدان الملصق'
        where customer_id = '22222222-2222-2222-2222-222222222222' and revoked_at is null
        returning 1
     )
     insert into customer_qr_tokens (customer_id)
     select '22222222-2222-2222-2222-222222222222' from revoked $$,
  'يقبل رمزًا جديدًا بعد إبطال السابق'
);

-- ── qr_revoke_complete ────────────────────────────────────────────────────
select throws_ok(
  $$ update customer_qr_tokens set revoked_at = now()
      where customer_id = '22222222-2222-2222-2222-222222222222' and revoked_at is null $$,
  '23514', null, 'يرفض الإبطال بلا سبب ولا من أبطله'
);

-- ── orders_completed_requires_payment ─────────────────────────────────────
select throws_ok(
  $$ update orders set status = 'completed' where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'يرفض الاكتمال بلا دفع'
);

-- ── orders_payment_consistent ─────────────────────────────────────────────
select throws_ok(
  $$ update orders set payment_status = 'paid' where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'يرفض «مدفوع» بلا طريقة ووقت'
);

select lives_ok(
  $$ update orders set payment_status = 'paid', payment_method = 'cash_on_delivery',
            paid_at = now(), paid_recorded_by = '44444444-4444-4444-4444-444444444444'
      where id = '55555555-5555-5555-5555-555555555555' $$,
  'يقبل الدفع المتسق'
);

-- ── orders_invoice_complete ───────────────────────────────────────────────
select throws_ok(
  $$ update orders set invoice_number = 'INV-1' where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'يرفض رقم فاتورة بلا قيمة ووقت'
);

select lives_ok(
  $$ update orders set invoice_number = 'INV-1', invoice_amount = 4.500, invoiced_at = now()
      where id = '55555555-5555-5555-5555-555555555555' $$,
  'يقبل الفاتورة الكاملة'
);

-- ── orders_invoice_no_idx ─────────────────────────────────────────────────
-- الكود كان يتوقع خطأ التكرار 23505 بينما القيد مفقود في النظام السابق
select throws_ok(
  $$ insert into orders (customer_id, property_id, invoice_number, invoice_amount, invoiced_at)
     values ('22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111', 'INV-1', 9.000, now()) $$,
  '23505', null, 'يرفض رقم فاتورة مكرر'
);

-- ── orders_cancel_requires_reason ─────────────────────────────────────────
select throws_ok(
  $$ update orders set status = 'cancelled', cancelled_at = now(),
            cancelled_by = '44444444-4444-4444-4444-444444444444'
      where id = '55555555-5555-5555-5555-555555555555' $$,
  '23514', null, 'يرفض الإلغاء بلا سبب'
);

-- ── invoice_amount ────────────────────────────────────────────────────────
select throws_ok(
  $$ insert into orders (customer_id, property_id, invoice_number, invoice_amount, invoiced_at)
     values ('22222222-2222-2222-2222-222222222222',
             '11111111-1111-1111-1111-111111111111', 'INV-2', 0.050, now()) $$,
  '23514', null, 'يرفض قيمة فاتورة تحت الحد الأدنى'
);

-- ── order_photos ──────────────────────────────────────────────────────────
insert into order_photos (order_id, kind, storage_path, byte_size, sha256)
values ('55555555-5555-5555-5555-555555555555', 'pickup', 'p/1.jpg', 1000, 'aaa');

select throws_ok(
  $$ insert into order_photos (order_id, kind, storage_path, byte_size, sha256)
     values ('55555555-5555-5555-5555-555555555555', 'pickup', 'p/2.jpg', 1000, 'bbb') $$,
  '23505', null, 'يرفض صورتين من نوع واحد للطلب نفسه'
);

-- بصمة فريدة: تكشف إعادة استخدام صورة قديمة لتزييف حضور ميداني
select throws_ok(
  $$ insert into order_photos (order_id, kind, storage_path, byte_size, sha256)
     values ('55555555-5555-5555-5555-555555555555', 'delivery', 'p/3.jpg', 1000, 'aaa') $$,
  '23505', null, 'يرفض إعادة استخدام بصمة صورة سابقة'
);

select throws_ok(
  $$ insert into order_photos (order_id, kind, storage_path, byte_size, sha256)
     values ('55555555-5555-5555-5555-555555555555', 'intake', 'p/4.jpg', 3000000, 'ccc') $$,
  '23514', null, 'يرفض صورة أكبر من الحد'
);

-- ── properties_coords_together ────────────────────────────────────────────
select throws_ok(
  $$ insert into properties (code, name, latitude) values ('X1', 'ناقص', 23.5) $$,
  '23514', null, 'يرفض إحداثية واحدة بلا الأخرى'
);

select lives_ok(
  $$ insert into properties (code, name, latitude, longitude)
     values ('TSTX2', 'كامل', 23.588000, 58.382900) $$,
  'يقبل الإحداثيتين معًا'
);

-- ── properties.code ───────────────────────────────────────────────────────
select throws_ok(
  $$ insert into properties (code, name) values ('برج', 'رمز عربي') $$,
  '23514', null, 'يرفض رمز عقار بغير الصيغة المحددة'
);

-- ── سجل الحالات غير قابل للتعديل ──────────────────────────────────────────
select is(
  (select count(*)::int from order_status_history
    where order_id = '55555555-5555-5555-5555-555555555555'),
  1,
  'سجل الحالة يُكتب تلقائيًا عند إنشاء الطلب'
);

select lives_ok(
  $$ update order_status_history set to_status = 'completed'
      where order_id = '55555555-5555-5555-5555-555555555555' $$,
  'محاولة تعديل السجل لا ترفع خطأ (قاعدة do instead nothing)'
);

select is(
  (select to_status from order_status_history
    where order_id = '55555555-5555-5555-5555-555555555555'),
  'new'::order_status,
  'لكنها لا تغيّر شيئًا — السجل غير قابل للتعديل فعليًا'
);

select lives_ok(
  $$ delete from order_status_history where order_id = '55555555-5555-5555-5555-555555555555' $$,
  'محاولة الحذف لا ترفع خطأ'
);

select is(
  (select count(*)::int from order_status_history
    where order_id = '55555555-5555-5555-5555-555555555555'),
  1,
  'ولا تحذف شيئًا'
);

select * from finish();
rollback;
