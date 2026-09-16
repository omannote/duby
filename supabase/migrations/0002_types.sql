-- 0002 — الأنواع المعدودة.
-- المرجع: docs/plan/03-data-model.md

do $$
begin
  if not exists (select 1 from pg_type where typname = 'staff_role') then
    create type staff_role as enum ('courier', 'operator', 'manager', 'admin');
  end if;

  if not exists (select 1 from pg_type where typname = 'profile_status') then
    create type profile_status as enum ('incomplete', 'complete');
  end if;

  /*
   * `delivered` محذوفة عمدًا: في النظام السابق استُخدمت بمعنيين مختلفين في
   * فترتين، فأنتجت طلبات عالقة خارج تبويب المكتملة. بديلها out_for_delivery
   * بمعنى صريح، و completed هي التسليم المؤكد بالـQR والصورة.
   */
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type order_status as enum (
      'new',              -- جديد
      'confirmed',        -- مؤكد
      'picked_up',        -- تم الاستلام   (QR + صورة في الموقع)
      'processing',       -- قيد التنفيذ
      'ready',            -- جاهز
      'out_for_delivery', -- خرج للتوصيل   (فاتورة + رابط دفع)
      'completed',        -- مكتمل         (دفع + QR + صورة تسليم) — نهائية
      'cancelled'         -- ملغي
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type payment_status as enum ('unpaid', 'paid', 'refunded');
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type payment_method as enum ('thawani', 'cash_on_delivery', 'manual');
  end if;

  if not exists (select 1 from pg_type where typname = 'photo_kind') then
    create type photo_kind as enum ('intake', 'pickup', 'delivery', 'cash_handover');
  end if;

  if not exists (select 1 from pg_type where typname = 'otp_state') then
    create type otp_state as enum (
      'pending', 'sent', 'verified', 'failed', 'blocked', 'expired', 'superseded'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'outbox_state') then
    create type outbox_state as enum (
      'pending', 'sending', 'sent', 'failed', 'skipped', 'dead'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'settlement_state') then
    create type settlement_state as enum ('open', 'handed_over', 'verified', 'disputed');
  end if;

  if not exists (select 1 from pg_type where typname = 'handover_method') then
    create type handover_method as enum (
      'bank_deposit', 'transfer', 'office_handover', 'safe_drop'
    );
  end if;
end $$;
