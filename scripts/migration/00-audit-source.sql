-- 00 — تدقيق المصدر: تقرير للقراءة فقط عن حالة النظام القديم.
--
/*
 * يُنفَّذ مبكرًا (المرحلة 1 من خارطة الطريق) لا ليلة الترحيل. معرفة حجم الشذوذ
 * مبكرًا هي ما يحدد قواعد التحويل — واكتشافه قبل الإطلاق بأيام مفاجأة لا خطة.
 *
 * لا يكتب شيئًا. آمن على الإنتاج.
 */
\echo '── الأحجام ──────────────────────────────────────────────────────────'
select 'موظفون'   as entity, count(*) from src.staff
union all select 'عقارات',   count(*) from src.properties
union all select 'عملاء',    count(*) from src.customers
union all select 'مسحات',    count(*) from src.scan_events
union all select 'تحديات OTP', count(*) from src.otp_challenges
union all select 'طلبات',    count(*) from src.orders;

\echo ''
\echo '── توزيع الحالات × النسخة (ومعه دليل صورة التسليم) ─────────────────'
select
  o.workflow_version,
  o.status,
  count(*)                                                        as orders,
  count(*) filter (where o.delivery_photo_path is not null)        as with_delivery_photo,
  m.mapped_status
from src.orders o
join src.order_status_mapped m on m.id = o.id
group by o.workflow_version, o.status, m.mapped_status
order by o.workflow_version, o.status;

\echo ''
\echo '── الشذوذ ───────────────────────────────────────────────────────────'
select 'عميل بلا عقار' as issue, count(*) from src.customers where property_id is null
union all
select 'حالة قديمة لا خريطة لها', count(*) from src.order_status_mapped where mapped_status is null
union all
select 'مكتمل بعد التحويل وغير مدفوع', count(*) from src.order_status_mapped
 where mapped_status = 'completed' and payment_status <> 'paid'
union all
select 'مكتمل بلا تأكيد تسليم', count(*) from src.order_status_mapped
 where mapped_status = 'completed' and (delivery_confirmed_at is null or delivery_confirmed_by is null)
union all
select 'ملغي بلا سبب', count(*) from src.orders
 where status = 'cancelled' and length(btrim(coalesce(cancel_reason, ''))) < 3
union all
select 'طلب بلا صورة استلام', count(*) from src.order_status_mapped
 where mapped_status not in ('new','confirmed','cancelled') and pickup_photo_path is null
union all
select 'رقم فاتورة مكرر', count(*) from (
  select invoice_number from src.orders where invoice_number is not null
   group by 1 having count(*) > 1) t
union all
select 'هاتف مكرر بين الفعّالين', count(*) from (
  select phone from src.customers where is_active and phone is not null
   group by 1 having count(*) > 1) t
union all
select 'هاتف بصيغة غير مقبولة', count(*) from src.customers
 where phone is not null and phone !~ '^\+968[0-9]{8}$'
union all
select 'رمز QR مكرر', count(*) from (
  select qr_token from src.customers group by 1 having count(*) > 1) t
union all
select 'عميل في عقار محذوف أو معطّل', count(*) from src.customers c
  join src.properties p on p.id = c.property_id
 where p.deleted_at is not null or not p.is_active;

\echo ''
\echo '── الصور المتوقَّع نقلها ─────────────────────────────────────────────'
select 'صور الطلب' as kind, count(*) from src.orders where order_photo_path is not null
union all select 'صور الاستلام', count(*) from src.orders where pickup_photo_path is not null
union all select 'صور التسليم', count(*) from src.orders where delivery_photo_path is not null;

\echo ''
\echo '── النقد التاريخي (أساس التسوية الافتتاحية) ─────────────────────────'
select
  s.email,
  count(*)                       as cash_orders,
  coalesce(sum(o.invoice_amount), 0) as cash_total
from src.orders o
left join src.staff s on s.id = o.delivery_confirmed_by
where o.payment_method = 'cash_on_delivery' and o.payment_status = 'paid'
group by s.email;
