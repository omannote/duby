-- pgTAP — اختبارات الأساس.
-- قاعدة: كل قيد وكل سياسة لهما اختبار. قيد بلا اختبار لا يُدمج.

begin;
select plan(9);

-- ── البنية ────────────────────────────────────────────────────────────────
select has_schema('private', 'مخطط private موجود');
select has_table('public', 'app_settings', 'جدول الإعدادات موجود');
select has_function('public', 'health_check', 'دالة فحص الصحة موجودة');
select has_function('public', 'touch_updated_at', 'دالة تحديث الطابع موجودة');

-- ── RLS ───────────────────────────────────────────────────────────────────
select ok(
  (select relrowsecurity from pg_class where oid = 'public.app_settings'::regclass),
  'RLS مفعّل على app_settings'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'app_settings'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  'لا سياسة كتابة على app_settings لأي دور'
);

-- ── وصول anon ─────────────────────────────────────────────────────────────
select ok(
  not has_table_privilege('anon', 'public.app_settings', 'SELECT')
  or (select count(*)::int from pg_policies
       where tablename = 'app_settings' and 'anon' = any(roles)) = 0,
  'anon لا يملك سياسة قراءة على app_settings'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'anon لا يصل إلى مخطط private'
);

select ok(
  not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated لا يصل إلى مخطط private'
);

select * from finish();
rollback;
