-- بيانات بذرية للتطوير المحلي فقط. لا تُطبَّق على staging أو الإنتاج.
-- الهدف: مطور جديد يرى نظامًا مأهولًا فور التشغيل.

insert into public_holidays (holiday_date, label) values
  ('2026-01-01', 'رأس السنة'),
  ('2026-11-18', 'العيد الوطني')
on conflict (holiday_date) do nothing;

insert into properties (code, name, address, latitude, longitude) values
  ('BRJ1', 'برج النهضة',  'الخوير، مسقط',  23.588000, 58.382900),
  ('BRJ2', 'مجمع الواحة', 'الغبرة، مسقط',  23.601000, 58.430000),
  ('BRJ3', 'أبراج السيفة', 'القرم، مسقط',   23.613000, 58.470000)
on conflict (code) do nothing;

-- عملاء في حالات مختلفة: مكتمل، غير مكتمل، ومعطَّل
do $$
declare
  v_property uuid := (select id from properties where code = 'BRJ1');
  v_customer uuid;
  i          int;
begin
  for i in 1..4 loop
    insert into customers (property_id, full_name, phone, floor_number, apartment_number,
                           profile_status, profile_completed_at)
    values (v_property, 'عميل تجريبي ' || i, '+9689123456' || i, i::text, (10 + i)::text,
            'complete', now())
    returning id into v_customer;

    insert into customer_qr_tokens (customer_id) values (v_customer);
  end loop;

  -- عميلان غير مكتملين: أُنشئ لهما رمز ولم يمسحاه بعد
  for i in 1..2 loop
    insert into customers (property_id)
    values ((select id from properties where code = 'BRJ2'))
    returning id into v_customer;

    insert into customer_qr_tokens (customer_id) values (v_customer);
  end loop;
end $$;

select format('seed: %s عقارات، %s عملاء، %s رموز',
              (select count(*) from properties),
              (select count(*) from customers),
              (select count(*) from customer_qr_tokens)) as status;
