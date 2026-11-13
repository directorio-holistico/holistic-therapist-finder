-- "My city is not listed": who can create, read, edit and resolve a request; what the guards refuse.
-- "Mi ciudad no está": quién crea, lee, edita y resuelve un pedido; qué rechazan las guardas.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000004' || k)::uuid, k || '@example.test', now() from unnest(array['b1','b2','b3','bd']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000004' || k)::uuid, ('00000000-0000-0000-0000-0000000004' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['b1','b2','b3','bd']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000004bd'::uuid, id from public.roles where code = 'admin';
-- b1, b2 unpublished; b3 suspended-like is tested through status below
insert into public.therapist_profiles (id, person_id, status_id)
  select ('20000000-0000-0000-0000-0000000004' || k)::uuid, ('10000000-0000-0000-0000-0000000004' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished')
  from unnest(array['b1','b2','b3']) k;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'suspended')
  where id = '20000000-0000-0000-0000-0000000004b3';

create temp table ids as
  select (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id
          join public.location_translations lt on lt.location_id = l.id and lt.name = 'Río Negro'
          where ll.code = 'region' limit 1) as region_id,
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id
          where ll.code = 'country' limit 1) as country_id,
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id
          join public.location_translations lt on lt.location_id = l.id and lt.name = 'Cinco Saltos'
          where ll.code = 'city' limit 1) as city_id;
grant select on ids to public;

-- 1) ANON: no access at all / ANON: sin acceso
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform count(*) from public.location_requests;
    raise exception 'anon must not read location_requests';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.resolve_location_request(1, 1);
    raise exception 'anon must not execute resolve_location_request';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;

-- 2) b1 (therapist) creates, edits and sees ONLY its own / b1 crea, edita y ve SOLO el suyo
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004b1","role":"authenticated"}', true);
do $$
declare
  r integer := (select region_id from ids);
  c integer := (select country_id from ids);
  n integer;
begin
  insert into public.location_requests (profile_id, region_id, city_name) values ('20000000-0000-0000-0000-0000000004b1', r, 'Villa Regina');
  -- a second OPEN request for the same profile is refused / un segundo pedido ABIERTO del mismo perfil se rechaza
  begin
    insert into public.location_requests (profile_id, region_id, city_name) values ('20000000-0000-0000-0000-0000000004b1', r, 'Otra');
    raise exception 'a second open request must be refused';
  exception when unique_violation then null;
  end;
  -- a country is not a region / un país no es una región
  update public.location_requests set region_id = c where profile_id = '20000000-0000-0000-0000-0000000004b1' and false;
  begin
    update public.location_requests set region_id = c where profile_id = '20000000-0000-0000-0000-0000000004b1';
    raise exception 'a non-region must be refused';
  exception when sqlstate '22023' then null;
  end;
  -- name rules / reglas del nombre
  begin
    update public.location_requests set city_name = ' x ' where profile_id = '20000000-0000-0000-0000-0000000004b1';
    raise exception 'a name with spaces must be refused';
  exception when check_violation then null;
  end;
  -- cannot create it for ANOTHER profile / no puede crearlo para OTRO perfil
  begin
    insert into public.location_requests (profile_id, region_id, city_name) values ('20000000-0000-0000-0000-0000000004b2', r, 'Ajena');
    raise exception 'must not create a request for another profile';
  exception when insufficient_privilege then null;
  end;
  -- cannot touch the resolution columns / no puede tocar las columnas de resolución
  begin
    update public.location_requests set resolved_at = now() where profile_id = '20000000-0000-0000-0000-0000000004b1';
    raise exception 'must not write resolved_at';
  exception when insufficient_privilege then null;
  end;
  update public.location_requests set city_name = 'Villa Regina Norte' where profile_id = '20000000-0000-0000-0000-0000000004b1';
  select count(*) into n from public.location_requests;
  if n <> 1 then raise exception 'b1 must see exactly its own request, saw %', n; end if;
end
$$;
reset role;

-- 3) b2 sees nothing of b1 and cannot edit or delete it / b2 no ve nada de b1 ni puede editarlo o borrarlo
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004b2","role":"authenticated"}', true);
do $$
declare n integer;
begin
  select count(*) into n from public.location_requests;
  if n <> 0 then raise exception 'b2 must not see other requests, saw %', n; end if;
  update public.location_requests set city_name = 'Hackeada';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'b2 must not update other requests'; end if;
  delete from public.location_requests;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'b2 must not delete other requests'; end if;
end
$$;
reset role;

-- 4) b3 (suspended profile) cannot create / b3 (perfil suspendido) no puede crear
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004b3","role":"authenticated"}', true);
do $$
begin
  begin
    insert into public.location_requests (profile_id, region_id, city_name)
      values ('20000000-0000-0000-0000-0000000004b3', (select region_id from ids), 'Suspendida');
    raise exception 'a suspended profile must not create a request';
  exception when sqlstate '55000' then null;
  end;
end
$$;
reset role;

-- 5) a therapist cannot resolve; the admin sees all and resolves with rules / un terapeuta no resuelve; el admin ve todo y resuelve con reglas
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004b1","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.resolve_location_request(1, (select city_id from ids));
    raise exception 'a therapist must not resolve';
  exception when sqlstate '42501' then null;
  end;
end
$$;
reset role;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004bd","role":"authenticated"}', true);
do $$
declare
  rid bigint;
  n integer;
begin
  select id into rid from public.location_requests limit 1;
  if rid is null then raise exception 'the admin must see the request'; end if;
  -- the city must be of city level / la ciudad debe ser de nivel ciudad
  begin
    perform public.resolve_location_request(rid, (select region_id from ids));
    raise exception 'a region is not a city';
  exception when sqlstate '22023' then null;
  end;
  perform public.resolve_location_request(rid, (select city_id from ids));
  select count(*) into n from public.location_requests
    where id = rid and resolved_at is not null and resolved_location_id = (select city_id from ids)
      and resolved_by_person_id = '10000000-0000-0000-0000-0000000004bd';
  if n <> 1 then raise exception 'the request must be resolved with who and when'; end if;
  begin
    perform public.resolve_location_request(rid, (select city_id from ids));
    raise exception 'resolving twice must be refused';
  exception when sqlstate '55000' then null;
  end;
end
$$;
reset role;

-- 6) after resolving, b1 cannot edit or delete it, and can open a new one / resuelto, b1 no lo edita ni borra, y puede abrir otro
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004b1","role":"authenticated"}', true);
do $$
declare n integer;
begin
  update public.location_requests set city_name = 'Cambio tardío';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'a resolved request must not be edited'; end if;
  delete from public.location_requests;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'a resolved request must not be deleted'; end if;
  insert into public.location_requests (profile_id, region_id, city_name)
    values ('20000000-0000-0000-0000-0000000004b1', (select region_id from ids), 'Otra ciudad');
end
$$;
reset role;
reset session authorization;

-- the audit log recorded the change with column names only / la auditoría registró el cambio solo con nombres de columnas
do $$
begin
  if not exists (select 1 from public.audit_log where table_name = 'location_requests' and operation = 'INSERT') then
    raise exception 'the audit log must record location_requests inserts';
  end if;
end
$$;

rollback;
\echo 'OK: location requests behave as designed / los pedidos de ciudad se comportan como se diseñó'
