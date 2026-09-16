-- 06 — التراجع: إزالة كل ما أدخله الترحيل.
--
/*
 * صالح **قبل الإطلاق فقط**. بعد أن يبدأ الموظفون العمل على النظام الجديد
 * يصبح التراجع نقلًا يدويًا لا سكربتًا (13-migration.md §8): الحذف هنا يقتصر
 * على الصفوف التي جاءت من المصدر، لكنه لا يستطيع فصل ما بُني فوقها لاحقًا.
 *
 * حارس صريح في أوله يرفض التشغيل إن وُجد نشاط لم يأتِ من الترحيل.
 *
 * معاملة واحدة: إمّا أن يُمحى كل شيء أو لا شيء.
 */
begin;

do $$
declare v_new_orders int;
begin
  select count(*) into v_new_orders
    from orders o
   where not exists (select 1 from src.orders s where s.id = o.id);

  if v_new_orders > 0 then
    raise exception
      'rollback_unsafe: % طلبًا أُنشئ بعد الترحيل. التراجع الآن يمحوه — انقله يدويًا أولًا.',
      v_new_orders;
  end if;
end $$;

/*
 * سجل الحالات محميّ بقاعدة تمنع الحذف — وهي حماية مقصودة تمنع محو أثر تغيير
 * حالة. التراجع هو الاستثناء الوحيد المشروع، فيرفعها ويعيدها داخل المعاملة
 * نفسها، ولا يبقى وقت تكون فيه القاعدة مكشوفة خارجها.
 */
drop rule if exists osh_no_delete on order_status_history;

delete from order_status_history h
 where exists (select 1 from src.orders s where s.id = h.order_id);

/*
 * محفّزان يقفان في وجه الحذف، وكلاهما حماية مقصودة: القفل النهائي يمنع تعديل
 * تسوية معتمدة، وإعادة الحساب تُعيد احتساب المتوقَّع عند حذف تحصيل — فتُنشئ
 * فرقًا يساوي المبلغ كله ويصطدم بقيد «الفرق الكبير يحتاج اعتمادًا».
 * يُعطَّلان هنا ويُعادان في المعاملة نفسها، كما فُعل بقاعدة سجل الحالات.
 */
alter table cash_collections  disable trigger trg_cash_collections_recalc;
alter table cash_settlements  disable trigger trg_settlement_final_lock;

delete from cash_collections c
 where exists (select 1 from src.orders s where s.id = c.order_id);

delete from cash_settlements s
 where s.notes like 'تسوية افتتاحية%';

alter table cash_settlements  enable trigger trg_settlement_final_lock;
alter table cash_collections  enable trigger trg_cash_collections_recalc;

delete from payments p
 where p.idempotency_key like 'migrated:%';

delete from orders o
 where exists (select 1 from src.orders s where s.id = o.id);

/*
 * تُعاد بعد حذف الطلبات لا قبله: `on delete cascade` من orders إلى سجل الحالات
 * يمرّ بنظام القواعد، فوجود القاعدة يجعل الحذف يفشل بـ«نتيجة غير متوقعة».
 * أثرٌ جانبي مفيد: ما دامت القاعدة قائمة يستحيل حذف طلب في التشغيل العادي —
 * وهو ما نريده.
 */
create rule osh_no_delete as on delete to order_status_history do instead nothing;

delete from otp_challenges c
 where exists (select 1 from src.otp_challenges s where s.id = c.id);

delete from scan_events e
 where exists (select 1 from src.scan_events s where s.id = e.id);

delete from customer_qr_tokens t
 where exists (select 1 from src.customers s where s.qr_token = t.token);

delete from customers c
 where exists (select 1 from src.customers s where s.id = c.id);

delete from properties p
 where exists (select 1 from src.properties s where s.id = p.id);

delete from staff st
 where exists (select 1 from src.staff s where s.id = st.id);

/*
 * إعدادات الإشعارات هي الصفوف الوحيدة التي عدّلها الترحيل ولم يُنشئها، فحذفها
 * لا يعيدها. تُستعاد من اللقطة التي التقطها 03 قبل التحديث.
 */
update order_status_settings t
   set notify_enabled       = (m.reason::jsonb ->> 'notify_enabled')::boolean,
       notification_message = m.reason::jsonb ->> 'notification_message'
  from (
    select distinct on (source_id) source_id, reason
      from private.migration_log
     where entity = 'order_status_settings' and action = 'message_replaced'
     order by source_id, created_at
  ) m
 where t.status::text = m.source_id;

-- السجل يبقى: أثر محاولة الترحيل وتراجعها جزء من التدقيق لا شيء يُمحى
insert into private.migration_log (entity, source_id, target_id, action, reason)
values ('run', null, null, 'rolled_back', 'تراجع كامل عن الترحيل');

commit;
