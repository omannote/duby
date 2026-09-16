-- قرارات الترحيل البشرية — جداول فارغة تُملأ قبل التشغيل.
--
/*
 * كل قرار في 13-migration.md §4 يسكن هنا، في مكان واحد قابل للمراجعة، لا
 * مبعثرًا في شيفرة التحويل. السكربت `02-preflight.sql` يرفض التشغيل ما دام
 * قرار واحد ناقصًا — فيستحيل أن يُرحَّل شيء بافتراض صامت.
 *
 * يُشغَّل بعد 01-source-adapter.sql، ثم تُملأ الجداول بـINSERT، ثم يُشغَّل
 * 02-preflight.sql.
 */
create schema if not exists src;

-- D0 — دور كل موظف فعّال في النظام الجديد.
-- «staff» القديم لم يكن يميّز بين من يعمل ميدانيًا ومن يدقّق، والتمييز الآن
-- هو ما يحدّد من يستلم النقد ومن يعتمد التسوية.
create table if not exists src.decision_staff_role (
  email text primary key,
  role  staff_role not null,
  note  text
);

-- D1 — عقار كل عميل يتيم.
create table if not exists src.decision_customer_property (
  customer_id uuid primary key,
  property_id uuid not null,
  note        text
);

/*
 * الهاتف المكرر: النظام الجديد يفرض فرادة الهاتف بين العملاء الفعّالين
 * (فهرس جزئي)، والقديم لم يفرضها. لكل هاتف مكرر يُحدَّد من يحتفظ به؛ البقية
 * تُرحَّل بهاتف فارغ وحالة ملف «ناقص» ليُستكمل عند أول مسح.
 */
create table if not exists src.decision_phone_owner (
  phone            text primary key,
  keep_customer_id uuid not null,
  note             text
);

/*
 * D4 — طلب تعني خريطتُه «مكتمل» لكنه غير مدفوع. القيد الجديد
 * `orders_completed_requires_payment` يرفضه، وهو قيد مقصود: النظام السابق
 * سمح بالتسليم بلا دفع وهذا أحد أسباب ضياع المال.
 *   mark_paid_cash — النقد حُصِّل فعلًا خارج النظام (يوثَّق في التسوية الافتتاحية)
 *   downgrade      — لم يُسلَّم فعلًا؛ يعود «خرج للتوصيل» ليُغلق في النظام الجديد
 */
create table if not exists src.decision_unpaid_completed (
  order_id   uuid primary key,
  resolution text not null check (resolution in ('mark_paid_cash', 'downgrade')),
  note       text
);

-- D5 — سبب الإلغاء للطلبات الملغاة بلا سبب مسجّل (القيد الجديد يشترط سببًا).
create table if not exists src.decision_cancel_reason (
  order_id uuid primary key,
  reason   text not null check (length(btrim(reason)) >= 3)
);

/*
 * المدقّق الذي تُنسب إليه التسويات الافتتاحية والإلغاءات المُرحَّلة. لا يصحّ
 * أن يكون مندوبًا في أي تسوية افتتاحية — «لا اعتماد ذاتي» تبقى قائمة.
 */
create table if not exists src.decision_migration_actor (
  singleton boolean primary key default true check (singleton),
  email     text not null
);
