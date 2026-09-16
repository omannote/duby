-- قرارات الترحيل لبيانات الاختبار — ما كان المالك سيملؤه يدويًا.
insert into src.decision_staff_role (email, role, note) values
  ('owner@myduby.test',  'admin',    'المالك — يعتمد التسويات عن بُعد'),
  ('field@myduby.test',  'courier',  'يعمل ميدانيًا ويستلم النقد'),
  ('office@myduby.test', 'operator', 'تدقّق وتتابع، لا تستلم نقدًا')
on conflict (email) do nothing;

insert into src.decision_customer_property (customer_id, property_id, note) values
  ('33333333-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000001',
   'راجعه المالك: الشقة في برج الموج')
on conflict (customer_id) do nothing;

insert into src.decision_phone_owner (phone, keep_customer_id, note) values
  ('+96891000001', '33333333-0000-0000-0000-000000000001', 'الأقدم والأكثر طلبات')
on conflict (phone) do nothing;

insert into src.decision_unpaid_completed (order_id, resolution, note) values
  ('77777777-0000-0000-0000-000000000007', 'mark_paid_cash',
   'المندوب أكّد تحصيله نقدًا وقت التسليم')
on conflict (order_id) do nothing;

insert into src.decision_cancel_reason (order_id, reason) values
  ('77777777-0000-0000-0000-000000000006', 'ألغاه العميل — مُرحَّل بلا سبب مسجّل')
on conflict (order_id) do nothing;

insert into src.decision_migration_actor (email) values ('owner@myduby.test')
on conflict (singleton) do nothing;
