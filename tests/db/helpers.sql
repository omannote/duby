-- أدوات مشتركة للاختبارات: تنتحل هوية موظف بدور محدد كما يفعل Supabase.
create or replace function test_seed_staff(p_role staff_role, p_name text default 'موظف اختبار')
returns table (staff_id uuid, user_id uuid)
language plpgsql
as $$
declare v_user uuid; v_staff uuid;
begin
  insert into auth.users (email) values (gen_random_uuid() || '@test.local')
  returning id into v_user;

  insert into staff (user_id, full_name, role) values (v_user, p_name, p_role)
  returning id into v_staff;

  return query select v_staff, v_user;
end;
$$;

create or replace function test_act_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id)::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function test_act_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end;
$$;

create or replace function test_reset_role()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'postgres', true);
end;
$$;
