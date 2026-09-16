#!/usr/bin/env node
/**
 * يقيس زمن التقارير على بيانات سنة كاملة.
 *
 * معيار القبول «كل تقرير < 2 ثانية» لا يُغلَق بالتقدير: يُولَّد حجم واقعي
 * ويُقاس فعلًا. البيانات تُحقن مباشرة في الجداول لأن الغرض قياس القراءة.
 *
 * تحذير: السكربت يفرّغ جداول الطلبات والعملاء والمسحات قبل التوليد وبعده.
 * يُشغَّل على قاعدة اختبار فقط، لا على بيانات حيّة.
 *
 * الاستخدام: pnpm perf:reports
 */
import { execFileSync } from 'node:child_process';

const DB_URL =
  process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

const BUDGET_MS = 2000;

/** حجم سنة تشغيل لمغسلة بهذا الحجم، مع هامش. */
const SCALE = {
  properties: 20,
  customers: 2_000,
  orders: 12_000,
  scans: 20_000,
};

function psql(sql) {
  return execFileSync(
    'psql',
    [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-t', '-A', '-c', sql],
    {
      encoding: 'utf8',
      maxBuffer: 32 * 1024 * 1024,
    },
  ).trim();
}

/** نصّ متعدد العبارات عبر stdin، لأن أوامر psql الخلفية (\timing) لا تمرّ بـ -c. */
function psqlScript(script) {
  return execFileSync(
    'psql',
    [DB_URL, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-t', '-A', '-f', '-'],
    {
      input: script,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    },
  );
}

const SEED = `
begin;

insert into auth.users (id, email)
select gen_random_uuid(), 'perf' || g || '@t.local' from generate_series(1, 5) g;

insert into staff (user_id, full_name, role)
select u.id, 'موظف ' || row_number() over (), 'courier'::staff_role
  from auth.users u where u.email like 'perf%';

insert into properties (code, name, is_active)
select 'PERF' || lpad(g::text, 3, '0'), 'عقار ' || g, true
  from generate_series(1, ${SCALE.properties}) g;

insert into customers (property_id, full_name, phone, floor_number, apartment_number,
                       profile_status, profile_completed_at)
select p.id,
       'عميل ' || g,
       '+9689' || lpad((1000000 + g)::text, 7, '0'),
       (g % 12 + 1)::text,
       (g % 40 + 1)::text,
       'complete', now()
  from generate_series(1, ${SCALE.customers}) g
  join lateral (select id from properties order by random() limit 1) p on true;

-- طلبات موزّعة على سنة كاملة وعلى كل الحالات
insert into orders (customer_id, property_id, status, status_changed_at, created_at,
                    pickup_confirmed_at, pickup_confirmed_by,
                    delivery_confirmed_at, delivery_confirmed_by,
                    cancelled_at, cancelled_by, cancel_reason,
                    invoice_number, invoice_amount, invoiced_at,
                    payment_status, payment_method, paid_at, paid_recorded_by)
select
  c.id, c.property_id,
  s.status,
  now() - (g || ' hours')::interval,
  now() - (g || ' hours')::interval,
  case when s.status not in ('new','confirmed','cancelled') then now() - (g || ' hours')::interval end,
  case when s.status not in ('new','confirmed','cancelled') then st.id end,
  case when s.status = 'completed' then now() - (g || ' hours')::interval end,
  case when s.status = 'completed' then st.id end,
  case when s.status = 'cancelled' then now() - (g || ' hours')::interval end,
  case when s.status = 'cancelled' then st.id end,
  case when s.status = 'cancelled' then 'إلغاء تجريبي للقياس' end,
  case when s.status in ('out_for_delivery','completed') then 'PERF-INV-' || g end,
  case when s.status in ('out_for_delivery','completed') then round((random() * 20 + 1)::numeric, 3) end,
  case when s.status in ('out_for_delivery','completed') then now() - (g || ' hours')::interval end,
  case when s.status = 'completed' then 'paid'::payment_status else 'unpaid'::payment_status end,
  case when s.status = 'completed' then 'cash_on_delivery'::payment_method end,
  case when s.status = 'completed' then now() - (g || ' hours')::interval end,
  case when s.status = 'completed' then st.id end
from generate_series(1, ${SCALE.orders}) g
join lateral (select id, property_id from customers order by random() limit 1) c on true
join lateral (select id from staff order by random() limit 1) st on true
join lateral (
  select (array['new','confirmed','picked_up','processing','ready',
                'out_for_delivery','completed','cancelled'])[1 + (g % 8)]::order_status as status
) s on true;

insert into scan_events (customer_id, scan_session_id, result, scanned_at,
                         otp_requested_at, verified_at, order_submitted_at)
select c.id, gen_random_uuid(),
       (array['order_submitted','otp_requested','invalid_qr','abandoned'])[1 + (g % 4)],
       now() - (g || ' minutes')::interval,
       case when g % 4 <> 2 then now() - (g || ' minutes')::interval end,
       case when g % 4 = 0 then now() - (g || ' minutes')::interval end,
       case when g % 4 = 0 then now() - (g || ' minutes')::interval end
  from generate_series(1, ${SCALE.scans}) g
  join lateral (select id from customers order by random() limit 1) c on true;

/*
 * سلسلة انتقالات واقعية لكل طلب. محفّز الإدراج يكتب سطرًا واحدًا فقط،
 * وسطر واحد يعني left_at فارغًا في mv_stage_durations — أي عرض خالٍ
 * فيصبح قياسه بلا معنى. السطور هنا موزّعة بين created_at والآن،
 * وسطر المحفّز يغلق آخر مرحلة.
 */
insert into order_status_history (order_id, from_status, to_status, changed_by, changed_at)
select o.id,
       case when k > 1 then chain.arr[k - 1] end,
       chain.arr[k],
       coalesce(o.pickup_confirmed_by, o.cancelled_by),
       o.created_at + (k * (now() - o.created_at) / (chain.len + 1))
  from orders o
  join lateral (
    select a.arr, array_length(a.arr, 1) as len
      from (
        select (array['new','confirmed','picked_up','processing','ready','out_for_delivery']::order_status[])
                 [1 : case o.status
                        when 'new'              then 0
                        when 'confirmed'        then 1
                        when 'picked_up'        then 2
                        when 'processing'       then 3
                        when 'ready'            then 4
                        when 'out_for_delivery' then 5
                        when 'completed'        then 6
                        when 'cancelled'        then 2
                      end] as arr
      ) a
  ) chain on chain.len is not null
  cross join lateral generate_series(1, chain.len) k;

commit;
`;

/*
 * تنظيف: order_status_history محميّ بقاعدة تمنع الحذف (حتى عبر cascade)،
 * فالتفريغ هو الوسيلة الوحيدة. السكربت يفترض قاعدة اختبار لا بيانات حيّة.
 * يُنفَّذ قبل التوليد أيضًا حتى لا تُسقط بقايا تشغيل فاشل التشغيلَ التالي.
 */
const CLEANUP = `set client_min_messages = warning;
  truncate order_status_history, scan_events, orders, customers cascade;
  delete from properties where code like 'PERF%';
  delete from staff where user_id in (select id from auth.users where email like 'perf%');
  delete from auth.users where email like 'perf%';`;

const REPORTS = [
  ['المؤشرات', 'select * from v_dashboard_kpis'],
  ['حسب الحالة', 'select * from v_orders_by_status'],
  ['حسب العقار', 'select * from v_orders_by_property'],
  ['قمع المسح', 'select * from v_scan_funnel order by business_date desc limit 90'],
  ['أعمار الفواتير', 'select * from v_unpaid_aging order by days_outstanding desc limit 200'],
  ['الإيرادات', 'select * from v_revenue_by_method order by business_date desc limit 90'],
  ['الطلبات المتوقفة', 'select * from v_stale_orders order by hours_in_status desc limit 200'],
  ['أداء المندوبين', 'select * from v_courier_performance'],
  ['زمن المراحل', 'select * from mv_stage_durations'],
];

console.log('توليد بيانات سنة كاملة…');
psqlScript(CLEANUP);
psql(SEED);

const counts = psql(`
  select format('عقارات %s · عملاء %s · طلبات %s · سجل حالات %s · مسحات %s',
    (select count(*) from properties), (select count(*) from customers),
    (select count(*) from orders), (select count(*) from order_status_history),
    (select count(*) from scan_events))
`);
console.log(counts);

console.log('\nتحديث العرض المادي…');
const refreshStart = performance.now();
psql('select fn_refresh_reports()');
console.log(`  استغرق ${Math.round(performance.now() - refreshStart)}ms\n`);

// ينتحل هوية مشرف: أوسع رؤية، فأثقل استعلام
const actAs = psql(`select u.id from auth.users u join staff s on s.user_id = u.id limit 1`);
psql(`update staff set role = 'manager' where user_id = '${actAs}'`);

let failed = 0;
console.log('زمن كل تقرير (ثلاث قراءات، الأبطأ):\n');

for (const [name, query] of REPORTS) {
  /*
   * القياس بـ \timing لا بساعة Node: زمن إقلاع عملية psql ليس جزءًا من
   * زمن التقرير، وإدخاله في الرقم يجعل القياس يبالغ بلا سبب.
   */
  const out = psqlScript(
    `set role authenticated;
     select set_config('request.jwt.claims', '{"sub":"${actAs}"}', false);
     \\timing on
     ${query};
     ${query};
     ${query};`,
  );

  const times = [...out.matchAll(/^Time: ([\d.]+) ms/gm)].map((m) => Number(m[1]));
  if (times.length !== 3) {
    throw new Error(`تعذّر قياس «${name}»: ${times.length} قراءة بدل 3`);
  }

  const ms = Math.round(Math.max(...times));
  const ok = ms < BUDGET_MS;
  if (!ok) failed += 1;

  console.log(`  ${ok ? '✓' : '✗'} ${name.padEnd(20)} ${String(ms).padStart(5)}ms`);
}

psqlScript(CLEANUP);

if (failed > 0) {
  console.error(`\n✗ ${failed} تقارير تجاوزت ${BUDGET_MS}ms`);
  process.exit(1);
}

console.log(`\n✓ كل التقارير دون ${BUDGET_MS}ms`);
