-- 0023 — زمن كل مرحلة.
--
/*
 * هذا التجميع هو الوحيد الثقيل فعلًا: نافذة على سجل الحالات كله لحساب الفرق
 * بين كل انتقال والذي يليه. جعله ماديًا يُبقي التقرير سريعًا مهما كبر السجل.
 *
 * العرض المادي لا تسري عليه RLS — ولهذا لا يحوي أي بيان يخص شخصًا: أرقام
 * مجمّعة عن المراحل لا عن الموظفين ولا العملاء.
 */
create materialized view if not exists mv_stage_durations as
with transitions as (
  select
    h.order_id,
    h.to_status                                                        as stage,
    h.changed_at,
    lead(h.changed_at) over (partition by h.order_id order by h.changed_at) as left_at
  from order_status_history h
)
select
  t.stage,
  count(*)::int                                                        as sample_size,
  round(avg(extract(epoch from (t.left_at - t.changed_at)) / 3600)::numeric, 2) as avg_hours,
  round((percentile_cont(0.5) within group (
    order by extract(epoch from (t.left_at - t.changed_at)) / 3600))::numeric, 2) as median_hours,
  round((percentile_cont(0.95) within group (
    order by extract(epoch from (t.left_at - t.changed_at)) / 3600))::numeric, 2) as p95_hours,
  max(t.changed_at)                                                    as latest_sample
from transitions t
where t.left_at is not null
group by t.stage;

create unique index if not exists mv_stage_durations_stage_idx on mv_stage_durations(stage);

-- فهارس تخدم الاستعلام الذي يبنيه
create index if not exists osh_order_changed_idx on order_status_history(order_id, changed_at);

/*
 * وقت آخر تحديث يُسجَّل صراحةً: من دونه لا تُميّز لوحةُ الصحة بين عرض محدَّث
 * لتوّه وعرض توقّف تحديثه منذ أيام، والرقمان يبدوان سواءً على الشاشة.
 */
create table if not exists private.report_refreshes (
  view_name    text primary key,
  refreshed_at timestamptz not null default now(),
  duration_ms  int
);

create or replace function fn_refresh_reports()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_started timestamptz := clock_timestamp();
begin
  begin
    -- concurrently يتطلب فهرسًا فريدًا، ويُبقي العرض قابلًا للقراءة أثناء التحديث
    refresh materialized view concurrently mv_stage_durations;
  exception
    when others then
      -- أول تحديث لا يمكن أن يكون concurrently
      refresh materialized view mv_stage_durations;
  end;

  insert into private.report_refreshes (view_name, refreshed_at, duration_ms)
  values ('mv_stage_durations', now(),
          (extract(epoch from (clock_timestamp() - v_started)) * 1000)::int)
  on conflict (view_name) do update
     set refreshed_at = excluded.refreshed_at,
         duration_ms  = excluded.duration_ms;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('refreshed_at', now()));
end;
$$;

revoke all on function fn_refresh_reports() from public, anon, authenticated;
grant execute on function fn_refresh_reports() to service_role;

grant select on mv_stage_durations to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'duby-refresh-reports',
      '*/30 * * * *',
      $cron$ select fn_refresh_reports() $cron$
    );
  end if;
end $$;
