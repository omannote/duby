-- الصلاحيات: الواجهة لا تملك كتابة واحدة، على أي جدول، الآن أو مستقبلًا.
--
/*
 * هذا الملف موجود بسبب ثغرة حقيقية: Supabase يمنح anon وauthenticated كل
 * الصلاحيات على جداول public افتراضيًا، والهجرة 0011 نزعتها عن anon ونسيت
 * authenticated. سياسات RLS حجبت insert/update/delete، لكن **TRUNCATE لا
 * تخضع لـRLS**، فكان أي حامل جلسة موظف يستطيع تفريغ أي جدول.
 *
 * الفحص هنا عامّ لا مُعدَّد: يمرّ على كل جدول في المخطط، فأي جدول جديد يُنشأ
 * بالصلاحية الافتراضية يُسقط الاختبار فورًا بدل أن ينتظر ثغرةً تُكتشف لاحقًا.
 */
begin;
select plan(7);

/*
 * جداول الامتدادات مستثناة: pgTAP يُثبَّت في قواعد الاختبار وحدها ولا يصل
 * الإنتاج، ولا نملك صلاحية تعديل منحه. استثناؤه هنا لا يُخفي شيئًا من
 * جداولنا — والفحص يبقى عامًّا على كل ما ننشئه.
 */
create or replace view test_app_grants as
select g.*
  from information_schema.role_table_grants g
  join pg_class c on c.relname = g.table_name
                 and c.relnamespace = 'public'::regnamespace
 where g.table_schema = 'public'
   and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e');

select is(
  (select count(*)::int
     from test_app_grants
    where grantee in ('anon', 'authenticated')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  0,
  'لا صلاحية كتابة لـanon أو authenticated على أي جدول'
);

-- TRUNCATE وحدها: لا تخضع لـRLS، فغيابها هو الحماية الوحيدة
select is(
  (select count(*)::int
     from test_app_grants
    where grantee in ('anon', 'authenticated')
      and privilege_type = 'TRUNCATE'),
  0,
  'ولا صلاحية TRUNCATE — وهي التي لا تحجبها RLS'
);

select is(
  (select count(*)::int
     from test_app_grants
    where grantee = 'anon'),
  0,
  'anon لا يملك أي وصول: صفحة العميل تعمل عبر Edge Function وحدها'
);

-- القراءة تبقى: العمل اليومي يحتاجها، والحجب بالسياسات لا بالصلاحيات
select cmp_ok(
  (select count(*)::int
     from test_app_grants
    where grantee = 'authenticated'
      and privilege_type = 'SELECT'),
  '>=', 10,
  'والقراءة باقية للموظف على الجداول التشغيلية'
);

select is(
  (select count(*)::int
     from test_app_grants
    where grantee = 'authenticated'
      and table_name in ('otp_challenges', 'order_submissions')),
  0,
  'otp_challenges و order_submissions بلا أي وصول — ولا قراءة'
);

/*
 * الصلاحيات الافتراضية للجداول القادمة: بدون نزعها يعود الثقب مع أول جدول
 * تُنشئه هجرة لاحقة، ويمرّ الفحص أعلاه لأنه يرى الحاضر لا المستقبل.
 */
/*
 * الافتراضي الذي يخصّ الدور الذي تعمل به الهجرات (postgres). هناك افتراضيّ
 * ثانٍ يخصّ supabase_admin ولا نملك تغييره، لكن لا شيء في هذا المستودع يُنشئ
 * جدولًا به.
 */
select is(
  (select count(*)::int
     from pg_default_acl d
     join pg_namespace n on n.oid = d.defaclnamespace
    where n.nspname = 'public' and d.defaclobjtype = 'r'
      and d.defaclrole = 'postgres'::regrole
      and array_to_string(d.defaclacl, ',') ~ '(anon|authenticated)=[^/,]*[awdD]'),
  0,
  'ولا صلاحية كتابة افتراضية لجدول يُنشأ لاحقًا'
);

-- service_role هو من يكتب: وظائف Edge تعمل به ويتجاوز RLS
select cmp_ok(
  (select count(*)::int
     from test_app_grants
    where grantee = 'service_role'
      and privilege_type = 'INSERT'),
  '>=', 10,
  'service_role يحتفظ بصلاحياته كاملة'
);

select * from finish();
rollback;
