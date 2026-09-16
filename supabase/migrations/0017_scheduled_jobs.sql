-- 0017 — المهام المجدولة.
--
-- pg_cron غير متاح في كل بيئة (القاعدة المحلية بلا Docker مثلًا)، فالجدولة
-- اختيارية والدوال تعمل بدونها. هذا يمنع فشل الهجرة في بيئة ناقصة.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    /*
     * المصالحة: الطبقة الثالثة من تأكيد الدفع.
     * تلتقط دفعة نجحت وأُغلق المتصفح قبل العودة ولم يصل webhookها.
     * النظام السابق يملك الطبقة الثانية وحدها، فكانت تلك الدفعة تبقى «غير
     * مدفوعة» ولا يمكن تسليم طلبها.
     */
    perform cron.schedule(
      'duby-payments-reconcile',
      '*/15 * * * *',
      $cron$ select net.http_post(
        url := current_setting('app.functions_url', true) || '/payments-reconcile',
        headers := jsonb_build_object('Authorization',
                     'Bearer ' || current_setting('app.service_key', true))
      ) $cron$
    );

    -- تنظيف يومي وفق سياسة الاحتفاظ
    perform cron.schedule(
      'duby-retention-cleanup',
      '0 2 * * *',
      $cron$ select fn_apply_retention() $cron$
    );
  end if;
end $$;

-- ── التنظيف وفق سياسة الاحتفاظ ────────────────────────────────────────────
create or replace function fn_apply_retention()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_otp   int;
  v_scans int;
begin
  delete from otp_challenges
   where created_at < now() - make_interval(days => setting_int('otp.retention_days', 90));
  get diagnostics v_otp = row_count;

  -- المسحات غير المكتملة فقط: المرتبطة بطلب تبقى مع طلبها
  delete from scan_events s
   where s.scanned_at < now() - make_interval(days => setting_int('scans.retention_days', 180))
     and not exists (select 1 from orders o where o.scan_event_id = s.id);
  get diagnostics v_scans = row_count;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'otp_deleted', v_otp, 'scans_deleted', v_scans));
end;
$$;

revoke all on function fn_apply_retention() from public, anon, authenticated;
grant execute on function fn_apply_retention() to service_role;

insert into app_settings (key, value, description) values
  ('otp.retention_days', '90'::jsonb, 'مدة الاحتفاظ بتحديات التحقق'),
  ('scans.retention_days', '180'::jsonb, 'مدة الاحتفاظ بالمسحات غير المكتملة')
on conflict (key) do nothing;
