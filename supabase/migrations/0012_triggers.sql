-- 0012 — المحفّزات: حارس الانتقالات، سجل الحالات، القفل النهائي، التدقيق.

-- ── مصفوفة الانتقالات المسموحة ───────────────────────────────────────────
-- المرجع: docs/plan/04-domain-flows.md القسم 1. أي خانة غير مذكورة مرفوضة.
create or replace function order_transition_allowed(from_status order_status, to_status order_status)
returns boolean
language sql
immutable
as $$
  select (from_status, to_status) in (
    ('new',              'confirmed'),
    ('confirmed',        'picked_up'),
    ('picked_up',        'processing'),
    ('processing',       'ready'),
    ('ready',            'out_for_delivery'),
    ('out_for_delivery', 'completed'),
    -- الإلغاء متاح حتى ما قبل الاكتمال
    ('new',              'cancelled'),
    ('confirmed',        'cancelled'),
    ('picked_up',        'cancelled'),
    ('processing',       'cancelled'),
    ('ready',            'cancelled'),
    ('out_for_delivery', 'cancelled')
  )
$$;

create or replace function trg_orders_guard_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  -- الحالة النهائية مقفلة: لا تغيير بعدها بأي وسيلة
  if old.status in ('completed', 'cancelled') then
    raise exception 'order_final_locked: الطلب في حالة نهائية (%)', old.status
      using errcode = '23514';
  end if;

  if not order_transition_allowed(old.status, new.status) then
    raise exception 'invalid_transition: % ← %', old.status, new.status
      using errcode = '23514';
  end if;

  new.status_changed_at := now();
  return new;
end;
$$;

drop trigger if exists trg_orders_guard_transition on orders;
create trigger trg_orders_guard_transition
  before update of status on orders
  for each row execute function trg_orders_guard_transition();

-- ── سجل الحالات ───────────────────────────────────────────────────────────
-- يُكتب هنا لا في كود التطبيق، فيستحيل تغيير حالة بلا سجل.
create or replace function trg_orders_status_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into order_status_history (order_id, from_status, to_status, changed_by, reason, request_id)
  values (
    new.id,
    case when tg_op = 'UPDATE' then old.status end,
    new.status,
    auth_staff_id(),
    case when new.status = 'cancelled' then new.cancel_reason end,
    nullif(current_setting('app.request_id', true), '')
  );
  return null;
end;
$$;

drop trigger if exists trg_orders_status_history_ins on orders;
create trigger trg_orders_status_history_ins
  after insert on orders
  for each row execute function trg_orders_status_history();

drop trigger if exists trg_orders_status_history_upd on orders;
create trigger trg_orders_status_history_upd
  after update of status on orders
  for each row when (old.status is distinct from new.status)
  execute function trg_orders_status_history();

-- ── القفل النهائي للطلب ───────────────────────────────────────────────────
-- الحالة النهائية لا تُقفل الحالة وحدها، بل كل حقول الطلب.
create or replace function trg_orders_final_lock()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('completed', 'cancelled')
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at')
  then
    raise exception 'order_final_locked: لا يمكن تعديل طلب في حالة نهائية'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_final_lock on orders;
create trigger trg_orders_final_lock
  before update on orders
  for each row execute function trg_orders_final_lock();

-- ── القفل النهائي للتسوية ─────────────────────────────────────────────────
/*
 * المطابقة البنكية استثناء مقصود: كشف الحساب يصل بعد أيام من الاعتماد،
 * فحقول bank_* وحدها تظل قابلة للكتابة بعده.
 */
create or replace function trg_settlement_final_lock()
returns trigger
language plpgsql
as $$
/*
 * variance مستثنى لأنه عمود محسوب (GENERATED STORED): في محفّز BEFORE تكون
 * قيمته في NEW فارغة دائمًا ولم تُحسب بعد، فمقارنتها تُظهر فرقًا وهميًا يقفل
 * حتى المطابقة البنكية المسموحة. استثناؤه آمن لأنه مشتق من confirmed_amount
 * وهو مشمول بالمقارنة.
 */
begin
  if old.state = 'verified'
     and (to_jsonb(new) - 'bank_reference' - 'bank_matched_at' - 'bank_matched_by'
                        - 'updated_at' - 'variance')
         is distinct from
         (to_jsonb(old) - 'bank_reference' - 'bank_matched_at' - 'bank_matched_by'
                        - 'updated_at' - 'variance')
  then
    raise exception 'settlement_locked: التسوية معتمدة ولا تقبل تعديلًا'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_settlement_final_lock on cash_settlements;
create trigger trg_settlement_final_lock
  before update on cash_settlements
  for each row execute function trg_settlement_final_lock();

-- ── إعادة حساب المتوقّع ───────────────────────────────────────────────────
-- expected_amount محسوب من التحصيلات، لا يُدخل يدويًا من أي نقطة نهاية.
create or replace function trg_settlement_recalc()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.settlement_id, old.settlement_id);
begin
  if target is null then
    return null;
  end if;

  update cash_settlements s
     set expected_amount = coalesce((
       select sum(c.amount) from cash_collections c
        where c.settlement_id = target and c.reversed_at is null
     ), 0)
   where s.id = target;

  return null;
end;
$$;

drop trigger if exists trg_cash_collections_recalc on cash_collections;
create trigger trg_cash_collections_recalc
  after insert or update or delete on cash_collections
  for each row execute function trg_settlement_recalc();

-- ── التدقيق ───────────────────────────────────────────────────────────────
create or replace function trg_write_audit()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  insert into private.audit_logs (actor_id, actor_role, action, entity, entity_id, before, after, request_id)
  values (
    auth_staff_id(),
    auth_role(),
    lower(tg_op),
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    nullif(current_setting('app.request_id', true), '')
  );
  return null;
end;
$$;

drop trigger if exists trg_audit_properties on properties;
create trigger trg_audit_properties
  after insert or update or delete on properties
  for each row execute function trg_write_audit();

drop trigger if exists trg_audit_customers on customers;
create trigger trg_audit_customers
  after insert or update or delete on customers
  for each row execute function trg_write_audit();

drop trigger if exists trg_audit_qr_tokens on customer_qr_tokens;
create trigger trg_audit_qr_tokens
  after insert or update or delete on customer_qr_tokens
  for each row execute function trg_write_audit();

drop trigger if exists trg_audit_staff on staff;
create trigger trg_audit_staff
  after insert or update or delete on staff
  for each row execute function trg_write_audit();

drop trigger if exists trg_audit_settlements on cash_settlements;
create trigger trg_audit_settlements
  after insert or update or delete on cash_settlements
  for each row execute function trg_write_audit();
