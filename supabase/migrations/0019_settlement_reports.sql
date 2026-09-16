-- 0019 — تقارير الصندوق.
--
-- عروض بـ security_invoker: تسري عليها سياسات RLS القائمة، فيرى المندوب
-- تسوياته وحدها ويرى المشغّل فأعلى الجميع — بلا فحص دور مكرر في كل تقرير.

-- ── النقد غير المودَع ─────────────────────────────────────────────────────
create or replace view v_pending_cash
with (security_invoker = true) as
select
  s.courier_id,
  st.full_name as courier_name,
  count(*)::int                        as open_settlements,
  min(s.business_date)                 as oldest_business_date,
  sum(s.expected_amount)               as unhanded_amount,
  -- المهلة بأيام العمل: البنك مغلق في العطل
  working_days_between(min(s.business_date), business_date_of()) as working_days_unhanded,
  working_days_between(min(s.business_date), business_date_of())
    > setting_int('cash.max_unhanded_days', 2)                   as blocked
from cash_settlements s
join staff st on st.id = s.courier_id
where s.state = 'open' and s.expected_amount > 0
group by s.courier_id, st.full_name;

-- ── بانتظار الاعتماد ──────────────────────────────────────────────────────
-- التأخير هنا على المدقّق لا على المندوب، ولا يسبب حجبًا.
create or replace view v_awaiting_verification
with (security_invoker = true) as
select
  s.id,
  s.courier_id,
  st.full_name as courier_name,
  s.business_date,
  s.expected_amount,
  s.declared_amount,
  s.handover_method,
  s.handover_reference,
  s.handover_photo_id,
  s.handover_at,
  s.state,
  round(extract(epoch from (now() - s.handover_at)) / 3600, 1) as hours_since_handover,
  extract(epoch from (now() - s.handover_at)) / 3600
    > setting_int('cash.verify_sla_hours', 24)                  as sla_breached
from cash_settlements s
join staff st on st.id = s.courier_id
where s.state in ('handed_over', 'disputed');

-- ── المطابقة البنكية المعلّقة ─────────────────────────────────────────────
-- الكاشف الحقيقي: كشف الحساب هو الحكم لا الصورة ولا الاعتماد اليومي.
create or replace view v_unmatched_deposits
with (security_invoker = true) as
select
  s.id,
  st.full_name as courier_name,
  s.business_date,
  s.confirmed_amount,
  s.handover_reference,
  s.verified_at,
  (business_date_of() - s.business_date)                        as days_unmatched,
  (business_date_of() - s.business_date)
    > setting_int('cash.bank_match_sla_days', 7)                as sla_breached
from cash_settlements s
join staff st on st.id = s.courier_id
where s.state = 'verified'
  and s.bank_matched_at is null
  and s.handover_method in ('bank_deposit', 'transfer');

-- ── استثناءات الإيداع ─────────────────────────────────────────────────────
-- المؤشر الذي يهم هو النسبة لا العدد: ارتفاعها يعني أن الاستثناء صار قاعدة.
create or replace view v_handover_exceptions
with (security_invoker = true) as
select
  s.id,
  st.full_name as courier_name,
  s.business_date,
  s.handover_method,
  s.handover_exception_reason,
  s.confirmed_amount,
  s.state
from cash_settlements s
join staff st on st.id = s.courier_id
where s.handover_method is not null and s.handover_method <> 'bank_deposit';

-- ── تاريخ الفروق وفجوة الإيداع ───────────────────────────────────────────
-- النمط المتكرر هو ما يهم، لا الحادثة المفردة.
create or replace view v_courier_variance_history
with (security_invoker = true) as
select
  s.courier_id,
  st.full_name as courier_name,
  count(*) filter (where s.state = 'verified')::int             as verified_count,
  count(*) filter (where s.variance <> 0)::int                  as variance_count,
  coalesce(sum(s.variance), 0)                                  as total_variance,
  coalesce(round(avg(s.variance), 3), 0)                        as average_variance,
  coalesce(round(avg(
    extract(epoch from (s.handover_at - (s.business_date + time '20:00') at time zone 'Asia/Muscat'))
    / 3600), 1), 0)                                             as average_handover_gap_hours
from cash_settlements s
join staff st on st.id = s.courier_id
where s.state in ('verified', 'disputed')
group by s.courier_id, st.full_name;

-- ── المطابقة اليومية ─────────────────────────────────────────────────────
-- مجموع التحصيلات مقابل مجموع الطلبات المدفوعة نقدًا: يجب أن يتطابقا.
create or replace view v_daily_cash_reconciliation
with (security_invoker = true) as
select
  c.business_date,
  sum(c.amount) filter (where c.reversed_at is null)            as collections_total,
  count(*) filter (where c.reversed_at is null)::int            as collections_count,
  count(*) filter (where c.reversed_at is not null)::int        as reversed_count
from cash_collections c
group by c.business_date;

grant select on
  v_pending_cash, v_awaiting_verification, v_unmatched_deposits,
  v_handover_exceptions, v_courier_variance_history, v_daily_cash_reconciliation
  to authenticated;

-- ── تذكير المندوب بالإيداع ───────────────────────────────────────────────
/*
 * المندوب يعمل وحده ولا أحد يذكّره. يُدرَج التذكير في الطابور لا يُرسل هنا:
 * الإرسال الفعلي في المرحلة الخامسة، والطابور يضمن ألا يضيع في الانتظار.
 */
create or replace function fn_enqueue_handover_reminders()
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare v_count int := 0;
begin
  insert into private.notification_outbox
    (kind, customer_id, recipient, template_name, params, idempotency_key)
  select
    'handover_reminder',
    null,
    st.phone,
    'ar_template',
    jsonb_build_array(format(
      'لديك نقد غير مودَع بقيمة %s ر.ع لتاريخ %s. يرجى إيداعه في حساب الشركة وتوثيق الإيصال من التطبيق.',
      to_char(s.expected_amount, 'FM999999990.000'), s.business_date)),
    format('handover_reminder:%s:%s', s.id, s.business_date)
  from cash_settlements s
  join staff st on st.id = s.courier_id
  where s.state = 'open'
    and s.expected_amount > 0
    and st.phone is not null
  on conflict (idempotency_key) do nothing;

  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('queued', v_count));
end;
$$;

revoke all on function fn_enqueue_handover_reminders() from public, anon, authenticated;
grant execute on function fn_enqueue_handover_reminders() to service_role;
