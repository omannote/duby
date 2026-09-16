-- ضوابط التسوية النقدية. أهمها: لا يعتمد أحد تسويته هو.
begin;
select plan(18);

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'courier@test.local'),
  ('a2222222-2222-2222-2222-222222222222', 'operator@test.local');
insert into staff (id, user_id, full_name, role) values
  ('b1111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'محمد', 'courier'),
  ('b2222222-2222-2222-2222-222222222222', 'a2222222-2222-2222-2222-222222222222', 'خالد', 'operator');

insert into properties (id, code, name)
values ('d1111111-1111-1111-1111-111111111111', 'TSTB', 'برج الاختبار ب');
insert into customers (id, property_id)
values ('e1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111');
insert into orders (id, customer_id, property_id) values
  ('f1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111'),
  ('f2222222-2222-2222-2222-222222222222', 'e1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111'),
  ('f3333333-3333-3333-3333-333333333333', 'e1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111');

insert into cash_settlements (id, courier_id, business_date)
values ('c1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111', '2026-09-16');

-- تحصيل بقيمة 10.000 ليكون المتوقّع معلومًا، فيعزل كل اختبار قيده وحده
insert into cash_collections (order_id, courier_id, settlement_id, amount, business_date)
values ('f3333333-3333-3333-3333-333333333333', 'b1111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 10.000, '2026-09-16');

-- ── أهم ضابط: لا اعتماد ذاتي، بلا استثناء لأي دور ────────────────────────
select throws_ok(
  $$ update cash_settlements
        set state = 'verified', confirmed_amount = 10.000,
            verified_by = 'b1111111-1111-1111-1111-111111111111', verified_at = now(),
            declared_amount = 10.000, handover_method = 'bank_deposit', handover_at = now()
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض اعتماد المندوب لتسويته هو'
);

select throws_ok(
  $$ update cash_settlements
        set approved_by = 'b1111111-1111-1111-1111-111111111111'
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض اعتماد المندوب لفرق تسويته هو'
);

-- ── التسليم الموثَّق ──────────────────────────────────────────────────────
select throws_ok(
  $$ update cash_settlements set state = 'handed_over', declared_amount = 10.000
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض التسليم بلا طريقة ولا وقت'
);

-- الإيداع البنكي — الطريقة المعتمدة — يتطلب إثباتًا ومرجعًا
select throws_ok(
  $$ update cash_settlements
        set state = 'handed_over', declared_amount = 10.000,
            handover_method = 'bank_deposit', handover_at = now()
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض الإيداع البنكي بلا صورة إثبات ولا رقم إيصال'
);

-- أي طريقة غير الإيداع البنكي استثناء يتطلب سببًا مكتوبًا
select throws_ok(
  $$ update cash_settlements
        set state = 'handed_over', declared_amount = 10.000,
            handover_method = 'safe_drop', handover_at = now()
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض طريقة استثنائية بلا سبب مكتوب'
);

select lives_ok(
  $$ update cash_settlements
        set state = 'handed_over', declared_amount = 10.000,
            handover_method = 'safe_drop', handover_at = now(),
            handover_exception_reason = 'البنك مغلق — عطلة العيد'
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  'يقبل الطريقة الاستثنائية مع سبب'
);

-- ── الاعتماد ──────────────────────────────────────────────────────────────
select throws_ok(
  $$ update cash_settlements set state = 'verified', confirmed_amount = 10.000
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض الاعتماد بلا مدقّق ولا وقت'
);

-- فرق غير صفري يتطلب سببًا
select throws_ok(
  $$ update cash_settlements
        set state = 'verified', confirmed_amount = 9.950,
            verified_by = 'b2222222-2222-2222-2222-222222222222', verified_at = now()
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض فرقًا غير صفري بلا سبب'
);

-- فرق خارج حد السماح (0.100) يتطلب اعتماد manager فأعلى
select throws_ok(
  $$ update cash_settlements
        set state = 'verified', confirmed_amount = 6.500,
            verified_by = 'b2222222-2222-2222-2222-222222222222', verified_at = now(),
            variance_reason = 'عجز كبير'
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض فرقًا خارج حد السماح بلا اعتماد المشرف'
);

select lives_ok(
  $$ update cash_settlements
        set state = 'verified', confirmed_amount = 9.950,
            verified_by = 'b2222222-2222-2222-2222-222222222222', verified_at = now(),
            variance_reason = 'عجز 0.050 — فكّة ناقصة'
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  'يقبل الاعتماد بفرق ضمن السماح وسبب مسجّل'
);

-- variance عمود محسوب، لا يُكتب
select is(
  (select variance from cash_settlements where id = 'c1111111-1111-1111-1111-111111111111'),
  -0.050::numeric(12,3),
  'الفرق محسوب آليًا = المؤكَّد − المتوقّع'
);

-- ── القفل النهائي ─────────────────────────────────────────────────────────
select throws_ok(
  $$ update cash_settlements set confirmed_amount = 99.000
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'التسوية المعتمدة مقفلة'
);

-- المطابقة البنكية الاستثناء الوحيد بعد الاعتماد
select lives_ok(
  $$ update cash_settlements
        set bank_reference = 'TXN-001', bank_matched_at = now(),
            bank_matched_by = 'b2222222-2222-2222-2222-222222222222'
      where id = 'c1111111-1111-1111-1111-111111111111' $$,
  'المطابقة البنكية مسموحة بعد الاعتماد'
);

-- ── تسوية واحدة لكل مندوب في اليوم ────────────────────────────────────────
select throws_ok(
  $$ insert into cash_settlements (courier_id, business_date)
     values ('b1111111-1111-1111-1111-111111111111', '2026-09-16') $$,
  '23505', null, 'يرفض تسويتين لمندوب واحد في يوم واحد'
);

-- ── المتوقّع محسوب من التحصيلات ───────────────────────────────────────────
insert into cash_settlements (id, courier_id, business_date)
values ('c2222222-2222-2222-2222-222222222222', 'b1111111-1111-1111-1111-111111111111', '2026-09-17');

insert into cash_collections (order_id, courier_id, settlement_id, amount, business_date) values
  ('f1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111',
   'c2222222-2222-2222-2222-222222222222', 4.500, '2026-09-17'),
  ('f2222222-2222-2222-2222-222222222222', 'b1111111-1111-1111-1111-111111111111',
   'c2222222-2222-2222-2222-222222222222', 6.250, '2026-09-17');

select is(
  (select expected_amount from cash_settlements where id = 'c2222222-2222-2222-2222-222222222222'),
  10.750::numeric(12,3),
  'المتوقّع يُحسب آليًا من التحصيلات'
);

-- إلغاء تحصيل يعيد الحساب
update cash_collections
   set reversed_at = now(), reversed_by = 'b1111111-1111-1111-1111-111111111111',
       reverse_reason = 'خطأ في المبلغ'
 where order_id = 'f2222222-2222-2222-2222-222222222222';

select is(
  (select expected_amount from cash_settlements where id = 'c2222222-2222-2222-2222-222222222222'),
  4.500::numeric(12,3),
  'إلغاء التحصيل يعيد حساب المتوقّع'
);

-- ── تحصيل واحد لكل طلب ────────────────────────────────────────────────────
select throws_ok(
  $$ insert into cash_collections (order_id, courier_id, amount, business_date)
     values ('f1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111',
             1.000, '2026-09-17') $$,
  '23505', null, 'يرفض تحصيلين لطلب واحد'
);

select throws_ok(
  $$ update cash_collections set reversed_at = now()
      where order_id = 'f1111111-1111-1111-1111-111111111111' $$,
  '23514', null, 'يرفض إلغاء التحصيل بلا سبب ولا من ألغاه'
);

select * from finish();
rollback;
