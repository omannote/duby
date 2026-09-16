-- 0024 — لوحة الصحة التشغيلية (admin).
--
/*
 * التقارير تجيب عن «كيف يسير العمل». هذه اللوحة تجيب عن سؤال آخر: «هل
 * النظام نفسه يعمل». الفرق مهم — طابور إشعارات متوقف أو مهمة مجدولة صامتة
 * لا يظهران في أي رقم تشغيلي، ويبقيان مخفيين حتى يشتكي عميل. النظام السابق
 * لم يملك هذه اللوحة، فكان اكتشاف العطل يأتي من الزبون لا من الشاشة.
 *
 * دالة لا عرض: أغلب المصادر في مخطط private (طابور الإشعارات، سجل
 * التحديثات) ولا تُمنح الواجهة أي صلاحية عليه. SECURITY DEFINER مع حارس
 * دور صريح هو المنفذ الوحيد، على نمط ADR-011: تُستدعى بجلسة الموظف نفسه.
 */
create or replace function fn_ops_health()
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_notifications jsonb;
  v_payments      jsonb;
  v_settlements   jsonb;
  v_orders        jsonb;
  v_journey       jsonb;
  v_reports       jsonb;
  v_jobs          jsonb := '[]'::jsonb;
begin
  if not auth_role_at_least('admin') then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  select jsonb_build_object(
    'pending',        count(*) filter (where state = 'pending'),
    'failed',         count(*) filter (where state = 'failed'),
    'dead',           count(*) filter (where state = 'dead'),
    'sent_last_hour', count(*) filter (where state = 'sent' and sent_at > now() - interval '1 hour'),
    'stale_pending',  count(*) filter (
                        where state in ('pending', 'sending')
                          and created_at < now() - interval '5 minutes'),
    -- نسبة نجاح الإرسال آخر يوم: الرقم الذي يكشف عطل جسر واتساب قبل الشكاوى
    'success_pct_24h', round(
                         100.0 * count(*) filter (
                           where state = 'sent' and sent_at > now() - interval '24 hours')
                         / nullif(count(*) filter (
                             where state in ('sent', 'failed', 'dead')
                               and created_at > now() - interval '24 hours'), 0), 1))
    into v_notifications
    from private.notification_outbox;

  /*
   * «معلّقة» تعني جلسة دفع أُنشئت ولم تُحسم منذ أكثر من ساعة: إما أن العميل
   * تركها، أو أن المصالحة توقفت. الرقم المرتفع هنا يعني تعطّل الطبقة الثالثة.
   */
  select jsonb_build_object(
    'stuck',            count(*) filter (
                          where status in ('created', 'reserved', 'pending')
                            and created_at < now() - interval '1 hour'),
    'paid_last_24h',    count(*) filter (
                          where status = 'paid' and updated_at > now() - interval '24 hours'),
    -- أي حالة يعيدها المزود غير المسار الطبيعي تُحسب فشلًا، فقائمتها ليست ثابتة
    'failed_last_24h',  count(*) filter (
                          where status not in ('created', 'reserved', 'pending', 'paid')
                            and updated_at > now() - interval '24 hours'))
    into v_payments
    from payments;

  select jsonb_build_object(
    'open',              count(*) filter (where state = 'open'),
    'awaiting_verify',   count(*) filter (where state = 'handed_over'),
    'verify_overdue',    count(*) filter (
                           where state = 'handed_over'
                             and handover_at < now()
                                 - make_interval(hours => setting_int('cash.verify_sla_hours', 24))),
    'disputed',          count(*) filter (where state = 'disputed'),
    'bank_unmatched',    count(*) filter (
                           where state = 'verified' and bank_matched_at is null
                             and handover_at < now()
                                 - make_interval(days => setting_int('cash.bank_match_sla_days', 7))),
    -- المبلغ لا العدد: «ثلاث تسويات مفتوحة» لا تقول كم من المال خارج الحساب
    'undeposited_amount', coalesce(sum(expected_amount) filter (where state = 'open'), 0),
    'exceptions_this_month', count(*) filter (
                               where handover_at >= date_trunc('month', now())
                                 and handover_method <> 'bank_deposit'),
    'handovers_this_month', count(*) filter (where handover_at >= date_trunc('month', now())))
    into v_settlements
    from cash_settlements;

  select jsonb_build_object(
    'stale',            count(*) filter (
                          where status not in ('completed', 'cancelled')
                            and status_changed_at < now()
                                - make_interval(hours => setting_int('orders.stale_alert_hours', 48))),
    'unpaid_invoices',  count(*) filter (
                          where payment_status = 'unpaid' and invoice_number is not null
                            and status <> 'cancelled'),
    'today',            count(*) filter (where business_date_of(created_at) = business_date_of()))
    into v_orders
    from orders;

  /*
   * رحلة العميل من المسح إلى الطلب. هبوط نسبة التحقق يعني عطلًا في إرسال
   * الرمز؛ هبوط التحويل وحده يعني تعثّرًا بعده.
   */
  select jsonb_build_object(
    'scans_24h',     count(*),
    'otp_success_pct', round(
                        100.0 * count(*) filter (where verified_at is not null)
                        / nullif(count(*) filter (where otp_requested_at is not null), 0), 1),
    'conversion_pct', round(
                        100.0 * count(*) filter (where order_submitted_at is not null)
                        / nullif(count(*), 0), 1))
    into v_journey
    from scan_events
   where scanned_at > now() - interval '24 hours';

  select jsonb_build_object(
    'stage_durations_refreshed_at', r.refreshed_at,
    'stage_durations_duration_ms',  r.duration_ms,
    'stage_durations_stale',        r.refreshed_at is null
                                    or r.refreshed_at < now() - interval '2 hours')
    into v_reports
    from (select * from private.report_refreshes where view_name = 'mv_stage_durations') r
   right join (select 1) one on true;

  /*
   * pg_cron غير موجود في كل بيئة (القاعدة المحلية بلا Docker)، فالقراءة
   * ديناميكية: لوحة الصحة يجب ألّا تنكسر حيث لا جدولة أصلًا.
   */
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
               'name', j.jobname,
               'schedule', j.schedule,
               'active', j.active,
               'last_status', d.status,
               'last_run_at', d.start_time)), '[]'::jsonb)
        from cron.job j
        left join lateral (
          select r.status, r.start_time
            from cron.job_run_details r
           where r.jobid = j.jobid
           order by r.start_time desc
           limit 1
        ) d on true
    $q$ into v_jobs;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'notifications', v_notifications,
    'payments',      v_payments,
    'settlements',   v_settlements,
    'orders',        v_orders,
    'journey',       v_journey,
    'reports',       v_reports,
    'jobs',          v_jobs,
    'checked_at',    now()));
end;
$$;

revoke all on function fn_ops_health() from public, anon;
grant execute on function fn_ops_health() to authenticated, service_role;
