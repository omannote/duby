-- حسابات الموظفين في المشروع الجديد — تُنشأ قبل الترحيل لا أثناءه.
/*
 * user_id لا يُنقل بين مشروعي Supabase: الحسابات تُدعى في المشروع الجديد أولًا،
 * ثم يربط الترحيل بالبريد. الفحص المسبق يرفض التشغيل إن نقص حساب.
 */
insert into auth.users (email) values
  ('owner@myduby.test'),
  ('field@myduby.test'),
  ('office@myduby.test')
on conflict (email) do nothing;
