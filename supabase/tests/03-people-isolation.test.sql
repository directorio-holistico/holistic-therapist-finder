-- People and roles: isolation between users, no writes, no escalation, anonymous access denied.
-- Personas y roles: aislamiento entre usuarios, sin escrituras, sin escalada de privilegios, anon denegado.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.
--
-- Fictional users: A and B are therapists, C is an admin, D is logged in but has no person record.
-- Usuarios ficticios: A y B son terapeutas, C es admin, D tiene sesión pero no tiene ficha.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'c@example.test');
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Persona A', 'a@example.test'),
  ('10000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2', 'Persona B', 'b@example.test'),
  ('10000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c3', 'Persona C', 'c@example.test');
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000a1'::uuid, id from public.roles where code = 'therapist'
  union all select '10000000-0000-0000-0000-0000000000b2'::uuid, id from public.roles where code = 'therapist'
  union all select '10000000-0000-0000-0000-0000000000c3'::uuid, id from public.roles where code = 'admin';

-- 1) Table constraints (as owner) / Restricciones de tabla (como dueño)
do $$
declare ok boolean;
begin
  -- active person without email / persona activa sin mail
  ok := false;
  begin insert into public.people (full_name) values ('Sin mail'); exception when check_violation then ok := true; end;
  if not ok then raise exception 'an active person without email was accepted'; end if;
  -- erased person that still has an email / persona eliminada que conserva el mail
  ok := false;
  begin insert into public.people (full_name, email, erased_at) values ('X', 'x@example.test', now()); exception when check_violation then ok := true; end;
  if not ok then raise exception 'an erased person with email was accepted'; end if;
  -- erased person that still has a login link / persona eliminada que conserva el vínculo de acceso
  ok := false;
  begin
    update public.people set erased_at = now(), email = null where id = '10000000-0000-0000-0000-0000000000a1';
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'an erased person that keeps auth_user_id was accepted'; end if;
  -- email must be lower case / el mail debe ir en minúsculas
  ok := false;
  begin insert into public.people (full_name, email) values ('Y', 'Y@Example.test'); exception when check_violation then ok := true; end;
  if not ok then raise exception 'a non-normalized email was accepted'; end if;
  -- duplicate email / mail repetido
  ok := false;
  begin insert into public.people (full_name, email) values ('Z', 'a@example.test'); exception when unique_violation then ok := true; end;
  if not ok then raise exception 'a duplicate email was accepted'; end if;
  -- one person per login / una persona por usuario de acceso
  ok := false;
  begin insert into public.people (auth_user_id, full_name, email)
        values ('00000000-0000-0000-0000-0000000000a1', 'Otra A', 'otra-a@example.test');
  exception when unique_violation then ok := true; end;
  if not ok then raise exception 'two people for one login were accepted'; end if;
  -- a valid erasure shape is accepted / una eliminación con forma válida se acepta
  update public.people set erased_at = now(), email = null, auth_user_id = null
    where id = '10000000-0000-0000-0000-0000000000b2';
  update public.people set erased_at = null, email = 'b@example.test', auth_user_id = '00000000-0000-0000-0000-0000000000b2'
    where id = '10000000-0000-0000-0000-0000000000b2';
end
$$;

-- 2) is_admin() permissions: authenticated yes; anon, service_role and PUBLIC no.
-- 2) Permisos de is_admin(): authenticated sí; anon, service_role y PUBLIC no.
do $$
begin
  if not has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE') then
    raise exception 'authenticated cannot execute is_admin()';
  end if;
  if has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
     or has_function_privilege('service_role', 'public.is_admin()', 'EXECUTE') then
    raise exception 'anon or service_role can execute is_admin()';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
             where p.oid = 'public.is_admin()'::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'PUBLIC can execute is_admin()';
  end if;
end
$$;

-- 3) User A (therapist) sees only their own data and cannot write or escalate.
-- 3) El usuario A (terapeuta) ve solo lo suyo y no puede escribir ni escalar privilegios.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  denied boolean;
  stmt text;
begin
  if (select count(*) from public.people) <> 1
     or (select auth_user_id from public.people) <> '00000000-0000-0000-0000-0000000000a1' then
    raise exception 'A must see exactly their own person row';
  end if;
  if (select count(*) from public.people where id = '10000000-0000-0000-0000-0000000000b2') <> 0 then
    raise exception 'A can see the person row of B';
  end if;
  if (select count(*) from public.person_roles) <> 1
     or (select count(*) from public.person_roles where person_id = '10000000-0000-0000-0000-0000000000b2') <> 0 then
    raise exception 'A must see only their own role';
  end if;
  if public.is_admin() then raise exception 'A must not be admin'; end if;

  foreach stmt in array array[
    $q$insert into public.people (full_name, email) values ('Nueva', 'nueva@example.test')$q$,
    $q$update public.people set full_name = 'Hackeado'$q$,
    $q$delete from public.people$q$,
    $q$insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000000a1', id from public.roles where code = 'admin'$q$,
    $q$update public.person_roles set role_id = (select id from public.roles where code = 'admin')$q$,
    $q$delete from public.person_roles$q$
  ] loop
    denied := false;
    begin execute stmt;
    exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'A could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 4) User B (therapist) sees only their own data (mirror of A).
-- 4) El usuario B (terapeuta) ve solo lo suyo (espejo de A).
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.people) <> 1
     or (select auth_user_id from public.people) <> '00000000-0000-0000-0000-0000000000b2' then
    raise exception 'B must see exactly their own person row';
  end if;
  if (select count(*) from public.person_roles) <> 1 then raise exception 'B must see only their own role'; end if;
  if public.is_admin() then raise exception 'B must not be admin'; end if;
end
$$;
reset role;
reset session authorization;

-- 5) User C (admin) sees everyone; still cannot write through the API.
-- 5) El usuario C (admin) ve a todos; tampoco escribe por la API.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare denied boolean := false;
begin
  if (select count(*) from public.people) <> 3 then raise exception 'admin must see the 3 people'; end if;
  if (select count(*) from public.person_roles) <> 3 then raise exception 'admin must see the 3 roles'; end if;
  if not public.is_admin() then raise exception 'C must be admin'; end if;
  begin delete from public.people;
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'admin could DELETE people through the API'; end if;
end
$$;
reset role;
reset session authorization;

-- 6) User D: logged in, but has no person record: sees nothing, is not admin.
-- 6) El usuario D: con sesión pero sin ficha: no ve nada y no es admin.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.people) <> 0 or (select count(*) from public.person_roles) <> 0 then
    raise exception 'a login without a person record must see nothing';
  end if;
  if public.is_admin() then raise exception 'D must not be admin'; end if;
end
$$;
reset role;
reset session authorization;

-- 7) Visitor (anon): denied by privileges on both tables and on is_admin().
-- 7) Visitante (anon): denegado por permisos en ambas tablas y en is_admin().
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare
  stmt text;
  denied boolean;
begin
  foreach stmt in array array[
    'select 1 from public.people',
    'select 1 from public.person_roles',
    'select public.is_admin()',
    $q$insert into public.people (full_name, email) values ('Anon', 'anon@example.test')$q$
  ] loop
    denied := false;
    begin execute stmt;
    exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: people and roles are isolated per user / personas y roles aislados por usuario'
