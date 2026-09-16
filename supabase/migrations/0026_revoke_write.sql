-- 0026 — نزع صلاحيات الكتابة عن أدوار الواجهة.
--
/*
 * Supabase يمنح anon وauthenticated كل الصلاحيات افتراضيًا على جداول public
 * (insert/update/delete/truncate). الهجرة 0011 نزعتها عن anon ونسيت
 * authenticated، فبقيت الواجهة تحمل صلاحية كتابة مباشرة على كل جدول.
 *
 * RLS كانت تحجب insert وupdate وdelete (لا سياسة كتابة فلا صفوف تُطابق)،
 * لكن **TRUNCATE لا تخضع لـRLS إطلاقًا**: أي حامل جلسة موظف صالحة كان
 * يستطيع تفريغ أي جدول. أُثبتت الثغرة عمليًا على مكدّس Supabase حيّ قبل هذا
 * الإصلاح.
 *
 * القاعدة المقصودة منذ ADR-011: الواجهة لا تملك صلاحية كتابة واحدة. كل كتابة
 * تمرّ بدالة SECURITY DEFINER تُستدعى بجلسة الموظف، أو بوظيفة Edge بمفتاح
 * service_role. هذه الهجرة تجعل القاعدة مفروضة لا موصوفة.
 */

/*
 * كائنًا كائنًا لا `on all tables`: الأخيرة تشمل جداول الامتدادات (pgTAP في
 * قواعد الاختبار) التي لا نملكها، فتُخرج تحذيرًا لكل عمود فيها — عشرات
 * الأسطر تُغرق مخرجات الهجرة وتُخفي ما يستحق القراءة.
 *
 * العروض مشمولة أيضًا: 0011 نزعت وصول anon قبل أن توجد عروض التقارير
 * والتسويات، فورثت هي المنح الافتراضي وبقي لـanon حق قراءتها. لم تكن تسريبًا
 * (كلها security_invoker مع حارس دور، فلا تعيد لـanon صفًّا)، لكن الطبقة
 * الأولى يجب أن تمنع لا أن تعتمد على الثانية.
 */
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as obj, c.relkind
      from pg_class c
     where c.relnamespace = 'public'::regnamespace
       and c.relkind in ('r', 'p', 'v', 'm')
       and not exists (
         select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on %s from anon, authenticated',
      r.obj);

    -- anon بلا أي وصول إطلاقًا: صفحة العميل تمرّ بوظيفة Edge وحدها
    execute format('revoke all on %s from anon', r.obj);
  end loop;
end $$;

-- والكائنات التي ستُنشأ لاحقًا: بدون هذا يعود الثقب مع أول جدول جديد
alter default privileges in schema public
  revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon;

-- التسلسلات: لا حاجة للواجهة بها، والكتابة تتم داخل الدوال
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as seq
      from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'S'
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on sequence %s from anon, authenticated', r.seq);
  end loop;
end $$;

alter default privileges in schema public revoke all on sequences from anon, authenticated;

/*
 * القراءة تبقى كما حدّدتها 0011 بالضبط: هذه الهجرة لا تمنح select لأحد ولا
 * تنزعه. otp_challenges و order_submissions يبقيان بلا أي وصول.
 */

-- service_role يتجاوز RLS ويحتاج الصلاحيات كاملة؛ تُثبَّت هنا صراحةً
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as obj, c.relkind
      from pg_class c
     where c.relnamespace = 'public'::regnamespace
       and c.relkind in ('r', 'p', 'S')
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('grant all on %s %s to service_role',
                   case when r.relkind = 'S' then 'sequence' else 'table' end, r.obj);
  end loop;
end $$;
