-- 01 — محوّل المصدر: عروض `src` فوق مخطط `legacy`.
--
/*
 * هذا هو **الملف الوحيد** الذي يُعدَّل إن اختلف مخطط النظام القديم عمّا نتوقعه.
 * بقية سكربتات الترحيل تقرأ من `src` ولا تعرف شيئًا عن `legacy`، فمواءمة
 * اسم عمود لا تمسّ منطق التحويل ولا التحقق.
 *
 * يُشغَّل بعد استعادة تفريغ الإنتاج في مخطط `legacy`:
 *   scripts/migration/attach-source.sh <رابط قاعدة المصدر>
 */
create schema if not exists src;

create or replace view src.staff as
select
  sp.id,
  sp.email,
  sp.full_name,
  sp.is_active,
  sp.created_at
from legacy.staff_profiles sp;

create or replace view src.properties as
select
  p.id,
  p.name,
  p.address,
  p.latitude,
  p.longitude,
  p.is_active,
  p.deleted_at,
  p.created_at
from legacy.properties p;

create or replace view src.customers as
select
  c.id,
  c.property_id,
  c.qr_token,
  c.full_name,
  c.phone,
  c.floor_number,
  c.apartment_number,
  c.profile_status,
  c.is_active,
  c.created_at
from legacy.customers c;

/*
 * مفردات النتيجة تغيّرت: التقارير الجديدة (قمع المسح) تعدّ قيمًا بعينها،
 * فترجمتها هنا تعني أن تقارير ما قبل الترحيل تُحتسب لا تُسقَط بصمت.
 */
create or replace view src.scan_events as
select
  s.id,
  s.customer_id,
  s.scan_session_id,
  s.ip_hash,
  s.user_agent,
  case s.result
    when 'order_created'  then 'order_submitted'
    when 'otp_sent'       then 'otp_requested'
    when 'otp_verified'   then 'otp_requested'
    when 'invalid_token'  then 'invalid_qr'
    when 'inactive'       then 'inactive_customer'
    else s.result
  end                as result,
  s.created_at as scanned_at
from legacy.scan_events s;

create or replace view src.otp_challenges as
select
  o.id,
  o.customer_id,
  o.scan_event_id,
  o.code_hash,
  o.phone as phone_snapshot,
  o.attempts,
  o.status,
  o.expires_at,
  o.verified_at,
  o.created_at
from legacy.otp_challenges o;

create or replace view src.orders as
select
  o.id,
  o.customer_id,
  o.property_id,
  o.status,
  o.workflow_version,
  o.scan_event_id,
  o.otp_challenge_id,
  o.order_photo_path,
  o.pickup_photo_path,
  o.delivery_photo_path,
  o.pickup_confirmed_at,
  o.pickup_confirmed_by,
  o.delivery_confirmed_at,
  o.delivery_confirmed_by,
  o.invoice_number,
  o.invoice_amount,
  o.payment_status,
  o.payment_method,
  o.thawani_session_id,
  o.paid_at,
  o.cancelled_at,
  o.cancel_reason,
  o.created_at,
  o.updated_at
from legacy.orders o;

create or replace view src.order_status_settings as
select s.status, s.notify_enabled, s.message
from legacy.order_status_settings s;

-- ── خريطة الحالات ─────────────────────────────────────────────────────────
/*
 * الدلالة لا النقل: `delivered` استُخدمت بمعنيين في فترتين، و`completed`
 * بالنسخة 1 كانت تعني «جاهز مع فاتورة». وجود صورة التسليم هو الدليل الحاسم —
 * من التقط صورة تسليم فقد سلّم فعلًا. (13-migration.md §2)
 */
create or replace view src.order_status_mapped as
select
  o.*,
  case
    when o.status = 'delivered' and o.workflow_version = 1            then 'completed'
    when o.status = 'delivered' and o.delivery_photo_path is not null then 'completed'
    when o.status = 'delivered'                                       then 'out_for_delivery'
    when o.status = 'completed' and o.workflow_version = 1            then 'out_for_delivery'
    when o.status = 'completed'                                       then 'completed'
    when o.status in ('new','confirmed','picked_up','processing','ready','cancelled')
                                                                      then o.status
  end as mapped_status
from src.orders o;
