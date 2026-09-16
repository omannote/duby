-- 05 — التحقق: بوابة قبول الترحيل.
--
/*
 * الترحيل لا يُعتمد إلا إذا كانت كل الأعداد متطابقة والشذوذ صفرًا. الفروق
 * المقصودة (سجل OTP قديم مستبعَد، موظف غير فعّال غير مُرحَّل) محسوبة في
 * الاستعلام نفسه لا مُبرَّرة شفويًا.
 *
 * `src.verify()` تعيد الجدول؛ الكتلة في آخر الملف ترفع استثناءً عند أي فشل.
 */
create or replace function src.verify()
returns table (check_name text, source_value numeric, target_value numeric, passed boolean)
language sql
as $$
  -- الموظفون المُرحَّلون = الفعّالون الذين لهم قرار دور
  select 'موظفون',
         (select count(*) from src.staff s
           where s.is_active
             and exists (select 1 from src.decision_staff_role d where d.email = s.email))::numeric,
         (select count(*) from staff)::numeric,
         (select count(*) from src.staff s
           where s.is_active
             and exists (select 1 from src.decision_staff_role d where d.email = s.email))
         = (select count(*) from staff)

  union all
  select 'عقارات',
         (select count(*) from src.properties)::numeric,
         (select count(*) from properties)::numeric,
         (select count(*) from src.properties) = (select count(*) from properties)

  union all
  select 'عملاء',
         (select count(*) from src.customers)::numeric,
         (select count(*) from customers)::numeric,
         (select count(*) from src.customers) = (select count(*) from customers)

  union all
  select 'طلبات',
         (select count(*) from src.orders)::numeric,
         (select count(*) from orders)::numeric,
         (select count(*) from src.orders) = (select count(*) from orders)

  union all
  select 'مسحات',
         (select count(*) from src.scan_events)::numeric,
         (select count(*) from scan_events)::numeric,
         (select count(*) from src.scan_events) = (select count(*) from scan_events)

  union all
  -- المال أولًا: فرق ريال واحد هنا يعني خطأ في التحويل لا في التقريب
  select 'مجموع الفواتير',
         (select coalesce(sum(invoice_amount), 0) from src.orders),
         (select coalesce(sum(invoice_amount), 0) from orders),
         (select coalesce(sum(invoice_amount), 0) from src.orders)
         = (select coalesce(sum(invoice_amount), 0) from orders)

  union all
  /*
   * المدفوع لا يطابق المصدر حرفيًا: قرارات D4 حوّلت طلبات «حُصِّلت نقدًا خارج
   * النظام» إلى مدفوعة. الفارق المقصود مضاف للمصدر صراحةً هنا — لا يُبرَّر شفويًا.
   */
  select 'مجموع المدفوع (مع قرارات D4)',
         (select coalesce(sum(invoice_amount), 0) from src.orders where payment_status = 'paid')
           + coalesce((select sum(o.invoice_amount) from orders o
                        join src.decision_unpaid_completed d on d.order_id = o.id
                       where d.resolution = 'mark_paid_cash'), 0),
         (select coalesce(sum(invoice_amount), 0) from orders where payment_status = 'paid'),
         (select coalesce(sum(invoice_amount), 0) from src.orders where payment_status = 'paid')
           + coalesce((select sum(o.invoice_amount) from orders o
                        join src.decision_unpaid_completed d on d.order_id = o.id
                       where d.resolution = 'mark_paid_cash'), 0)
         = (select coalesce(sum(invoice_amount), 0) from orders where payment_status = 'paid')

  union all
  -- كل رمز مطبوع لا بد أن يفتح: هذا هو الفحص الذي يمنع إعادة طباعة الملصقات
  select 'رموز QR سارية', (select count(*) from src.customers)::numeric,
         (select count(*) from src.customers sc
           where exists (select 1 from customer_qr_tokens t
                          where t.token = sc.qr_token and t.revoked_at is null))::numeric,
         (select count(*) from src.customers)
         = (select count(*) from src.customers sc
             where exists (select 1 from customer_qr_tokens t
                            where t.token = sc.qr_token and t.revoked_at is null))

  union all
  select 'طلبات يتيمة', 0,
         (select count(*) from orders o
           left join customers c on c.id = o.customer_id where c.id is null)::numeric,
         not exists (select 1 from orders o
                      left join customers c on c.id = o.customer_id where c.id is null)

  union all
  select 'حالات غير معروفة', 0,
         (select count(*) from orders
           where status::text not in ('new','confirmed','picked_up','processing',
                                      'ready','out_for_delivery','completed','cancelled'))::numeric,
         not exists (select 1 from orders
                      where status::text not in ('new','confirmed','picked_up','processing',
                                                 'ready','out_for_delivery','completed','cancelled'))

  union all
  select 'عملاء بلا عقار', 0, 0,
         not exists (select 1 from customers where property_id is null)

  union all
  -- التسوية الافتتاحية بفرق صفر: أي فرق يعني ذمة وهمية على مندوب يوم الإطلاق
  select 'فرق التسويات الافتتاحية', 0,
         (select coalesce(sum(abs(variance)), 0) from cash_settlements),
         (select coalesce(sum(abs(variance)), 0) from cash_settlements) = 0

  union all
  select 'تحصيلات مربوطة بتسوية',
         (select count(*) from cash_collections)::numeric,
         (select count(*) from cash_collections where settlement_id is not null)::numeric,
         (select count(*) from cash_collections)
         = (select count(*) from cash_collections where settlement_id is not null)

  union all
  select 'سجل حالات لكل طلب',
         (select count(*) from orders)::numeric,
         (select count(distinct order_id) from order_status_history)::numeric,
         (select count(*) from orders)
         = (select count(distinct order_id) from order_status_history)

  union all
  select 'سجل الترحيل مكتمل', 1,
         (select count(*) from private.migration_log
           where entity = 'run' and action = 'completed')::numeric,
         exists (select 1 from private.migration_log
                  where entity = 'run' and action = 'completed')

  order by 1
$$;

\echo '── التحقق من الترحيل ────────────────────────────────────────────────'
select * from src.verify();

\echo ''
\echo '── ما غُيّر معناه أثناء الترحيل ───────────────────────────────────────'
select entity, action, count(*) as rows
  from private.migration_log group by 1, 2 order by 1, 2;

do $$
declare v_failed int;
begin
  select count(*) into v_failed from src.verify() where not passed;

  if v_failed > 0 then
    raise exception 'verify_failed: % فحصًا لم يمر. لا تعتمد الترحيل.', v_failed;
  end if;

  raise notice 'اجتاز التحقق — الترحيل قابل للاعتماد.';
end $$;
