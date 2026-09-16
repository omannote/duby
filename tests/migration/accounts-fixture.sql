-- حسابات الموظفين في المشروع الجديد — تُنشأ قبل الترحيل لا أثناءه.
/*
 * user_id لا يُنقل بين مشروعي Supabase: الحسابات تُدعى في المشروع الجديد أولًا،
 * ثم يربط الترحيل بالبريد. الفحص المسبق يرفض التشغيل إن نقص حساب.
 */
/*
 * `where not exists` لا `on conflict (email)`: فرادة البريد في Supabase فهرس
 * جزئي لا قيد، و`on conflict` على عمود بلا قيد مطابق يفشل بـ«no unique or
 * exclusion constraint matching».
 */
insert into auth.users (id, email)
select gen_random_uuid(), e
  from (values ('owner@myduby.test'), ('field@myduby.test'), ('office@myduby.test')) as v(e)
 where not exists (select 1 from auth.users u where u.email = v.e);
