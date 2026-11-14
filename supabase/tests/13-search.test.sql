-- Search and unmet searches: result groups, filters, pagination, input validation, logging with no personal data.
-- Búsqueda y demanda no cubierta: grupos de resultados, filtros, paginación, validación, registro sin datos personales.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000001' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2','a3','a4','a5','a6','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000001' || k)::uuid, ('00000000-0000-0000-0000-0000000001' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2','a3','a4','a5','a6','ad']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000001ad'::uuid, id from public.roles where code = 'admin';

create function pg_temp.city(p_name text) returns integer language sql as $$
  select l.id from public.locations l join public.location_translations t on t.location_id = l.id
   join public.languages g on g.id = t.language_id and g.code = 'es'
   join public.location_levels ll on ll.id = l.level_id and ll.code = 'city' where t.name = p_name $$;

-- a1 Córdoba in-person | a2 Rosario remote | a3 Santiago remote | a4 Córdoba both | a5 Barcelona in-person | a6 Córdoba paused
-- Distinct approval dates fix the order inside a group / Fechas de aprobación distintas fijan el orden dentro del grupo
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000001' || x.k)::uuid, ('10000000-0000-0000-0000-0000000001' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - make_interval(days => x.d),
         pg_temp.city(x.city), x.name
  from (values ('a1','Córdoba',50,'Uno'), ('a2','Rosario',40,'Dos'), ('a3','Santiago',30,'Tres'),
               ('a4','Córdoba',20,'Cuatro'), ('a5','Barcelona',10,'Cinco'), ('a6','Córdoba',5,'Seis')) x(k, city, d, name);

insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000001' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+5435155500' || n
  from unnest(array['a1','a2','a3','a4','a5','a6']) with ordinality as u(k, n);
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select ('20000000-0000-0000-0000-0000000001' || k)::uuid, (select id from public.therapies where is_active order by id limit 1), 60
  from unnest(array['a1','a2','a3','a4','a5','a6']) k;
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
  select ('20000000-0000-0000-0000-0000000001' || x.k)::uuid, (select id from public.therapies where is_active order by id limit 1), m.id
  from (values ('a1','in_person'), ('a2','remote'), ('a3','remote'), ('a4','in_person'), ('a4','remote'), ('a5','in_person'), ('a6','in_person'), ('a6','remote')) x(k, mode)
  join public.service_modes m on m.code = x.mode;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in (select ('20000000-0000-0000-0000-0000000001' || k)::uuid from unnest(array['a1','a2','a3','a4','a5']) k);
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = ('20000000-0000-0000-0000-0000000001' || 'a6')::uuid;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused'), status_reason = 'test' where id = ('20000000-0000-0000-0000-0000000001' || 'a6')::uuid;

select set_config('test.t1', (select id::text from public.therapies where is_active order by id limit 1), true),
       set_config('test.t2', (select id::text from public.therapies where is_active order by id limit 1 offset 1), true),
       set_config('test.cordoba_city', pg_temp.city('Córdoba')::text, true);

-- region and country of the city of Córdoba / región y país de la ciudad de Córdoba
select set_config('test.cordoba_region', (select parent_id::text from public.locations where id = pg_temp.city('Córdoba')), true);
select set_config('test.arg', (select r.parent_id::text from public.locations r where r.id = (select parent_id from public.locations where id = pg_temp.city('Córdoba'))), true);
select set_config('test.rosario', pg_temp.city('Rosario')::text, true);

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare v_acl text;
begin
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.unmet_searches'::regclass) then
    raise exception 'unmet_searches has no RLS';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'unmet_searches'
              and column_name ~* '(ip|user|person|email|session|agent|device)') then
    raise exception 'unmet_searches must carry no personal or identifying column';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.search_profiles(integer,integer,text,integer,integer)'::regprocedure) then
    raise exception 'search_profiles must be SECURITY INVOKER';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.log_search(integer,integer,text)'::regprocedure) then
    raise exception 'log_search must be SECURITY DEFINER';
  end if;
  if not has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or not has_function_privilege('anon', 'public.log_search(integer,integer,text)', 'execute') then
    raise exception 'anon must execute search_profiles and log_search';
  end if;
  if has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.log_search(integer,integer,text)', 'execute') then
    raise exception 'authenticated must not execute search_profiles or log_search (anon only)';
  end if;
  if has_function_privilege('anon', 'public.purge_expired_unmet_searches()', 'execute')
     or has_function_privilege('authenticated', 'public.purge_expired_unmet_searches()', 'execute')
     or not has_function_privilege('service_role', 'public.purge_expired_unmet_searches()', 'execute') then
    raise exception 'purge_expired_unmet_searches must be executable by service_role only';
  end if;
  if has_function_privilege('service_role', 'public.log_search(integer,integer,text)', 'execute') then
    raise exception 'service_role should not execute log_search';
  end if;
  if not exists (select 1 from public.service_modes where code = 'in_person' and is_active)
     or not exists (select 1 from public.service_modes where code = 'remote' and is_active) then
    raise exception 'the service modes in_person and remote must exist (business rule of the groups)';
  end if;
end $$;

-- 2) SEARCH AS ANON / BÚSQUEDA COMO ANON
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);

do $$
declare
  t1 int := current_setting('test.t1')::int;
  city int := current_setting('test.cordoba_city')::int;
  reg int := current_setting('test.cordoba_region')::int;
  arg int := current_setting('test.arg')::int;
  got text; tot bigint;
begin
  -- city, no filter: group 1 = Uno, Cuatro; group 2 = Dos (remote, same country); group 3 = Tres (remote, abroad)
  select string_agg(result_group || ':' || display_name, ',' order by result_group, approved_at, profile_id), max(total_count)
    into got, tot from public.search_profiles(t1, city);
  if got <> '1:Uno,1:Cuatro,2:Dos,3:Tres' or tot <> 4 then raise exception 'city/no filter: got % (total %)', got, tot; end if;

  -- city + in person: only group 1 / ciudad + presencial: solo grupo 1
  select string_agg(result_group || ':' || display_name, ',' order by result_group, approved_at, profile_id), max(total_count)
    into got, tot from public.search_profiles(t1, city, 'in_person');
  if got <> '1:Uno,1:Cuatro' or tot <> 2 then raise exception 'city/in_person: got % (total %)', got, tot; end if;

  -- city + remote: Cuatro (group 1), Dos (2), Tres (3); Uno (in person only) is out
  select string_agg(result_group || ':' || display_name, ',' order by result_group, approved_at, profile_id), max(total_count)
    into got, tot from public.search_profiles(t1, city, 'remote');
  if got <> '1:Cuatro,2:Dos,3:Tres' or tot <> 3 then raise exception 'city/remote: got % (total %)', got, tot; end if;

  -- region: same as the city here (all Córdoba profiles are in that region)
  select string_agg(result_group || ':' || display_name, ',' order by result_group, approved_at, profile_id)
    into got from public.search_profiles(t1, reg);
  if got <> '1:Uno,1:Cuatro,2:Dos,3:Tres' then raise exception 'region: got %', got; end if;

  -- country: group 1 = every profile in Argentina (Uno, Dos, Cuatro); no group 2 (already the whole country); group 3 = Tres
  select string_agg(result_group || ':' || display_name, ',' order by result_group, approved_at, profile_id)
    into got from public.search_profiles(t1, arg);
  if got <> '1:Uno,1:Dos,1:Cuatro,3:Tres' then raise exception 'country: got %', got; end if;

  -- Barcelona (in person only) never shows for a Córdoba search; the paused one never shows at all
  if exists (select 1 from public.search_profiles(t1, city) where display_name in ('Cinco', 'Seis')) then
    raise exception 'Cinco/Seis must not appear';
  end if;

  -- a therapy nobody offers: zero rows / una terapia que nadie ofrece: cero filas
  if exists (select 1 from public.search_profiles(current_setting('test.t2')::int, city)) then
    raise exception 'unexpected result for a therapy nobody offers';
  end if;
end $$;

-- pagination: total_count is the full count on every page / paginación: total_count es el total en cada página
do $$
declare t1 int := current_setting('test.t1')::int; city int := current_setting('test.cordoba_city')::int; a text; b text; c text; tcs bigint[];
begin
  select string_agg(display_name, ','), array_agg(distinct total_count) into a, tcs from public.search_profiles(t1, city, null, 2, 0);
  select string_agg(display_name, ',') into b from public.search_profiles(t1, city, null, 2, 2);
  select string_agg(display_name, ',') into c from public.search_profiles(t1, city, null, 2, 4);
  if a <> 'Uno,Cuatro' or b <> 'Dos,Tres' or c is not null or tcs <> array[4::bigint] then
    raise exception 'pagination: page1 %, page2 %, page3 %, totals %', a, b, c, tcs;
  end if;
end $$;

-- invalid input is rejected with 22023 / la entrada inválida se rechaza con 22023
do $$
declare
  t1 int := current_setting('test.t1')::int; city int := current_setting('test.cordoba_city')::int;
  q text; failed int := 0;
begin
  foreach q in array array[
    'select * from public.search_profiles(-1, %2$s)',
    'select * from public.search_profiles(%1$s, -1)',
    'select * from public.search_profiles(%1$s, %2$s, ''inventado'')',
    'select * from public.search_profiles(%1$s, %2$s, null, 0, 0)',
    'select * from public.search_profiles(%1$s, %2$s, null, 51, 0)',
    'select * from public.search_profiles(%1$s, %2$s, null, null, 0)',
    'select * from public.search_profiles(%1$s, %2$s, null, 20, -1)',
    'select * from public.search_profiles(%1$s, %2$s, null, 20, 10001)',
    'select * from public.search_profiles(%1$s, %2$s, null, 20, null)'] loop
    begin
      execute format(q, t1, city);
      raise exception 'accepted: %', q;
    exception when sqlstate '22023' then failed := failed + 1;
    end;
  end loop;
  if failed <> 9 then raise exception 'expected 9 rejections, got %', failed; end if;
end $$;

-- anon cannot read or write the counters / anon no lee ni escribe los contadores
do $$
begin
  begin perform 1 from public.unmet_searches; raise exception 'anon read unmet_searches';
  exception when insufficient_privilege then null; end;
  begin insert into public.unmet_searches (therapy_id, location_id, day) values (1, 1, current_date); raise exception 'anon wrote unmet_searches';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_unmet_searches(); raise exception 'anon ran the purge';
  exception when insufficient_privilege then null; end;
end $$;

-- 3) LOGGING AS ANON / REGISTRO COMO ANON
do $$
declare
  t1 int := current_setting('test.t1')::int; t2 int := current_setting('test.t2')::int;
  city int := current_setting('test.cordoba_city')::int;
begin
  if public.log_search(t1, city) then raise exception 'a search WITH results must not be logged'; end if;
  if public.log_search(t1, city, 'remote') then raise exception 'a search WITH results (remote) must not be logged'; end if;
  if not public.log_search(t2, city) then raise exception 'a search with no results must be logged'; end if;
  if not public.log_search(t2, city) then raise exception 'second identical search must be logged'; end if;
  if not public.log_search(t2, city, 'in_person') then raise exception 'search with mode must be logged'; end if;
  begin perform public.log_search(null, city); raise exception 'accepted null therapy';
  exception when sqlstate '22023' then null; end;
  begin perform public.log_search(t2, -1); raise exception 'accepted unknown location';
  exception when sqlstate '22023' then null; end;
  begin perform public.log_search(-1, city); raise exception 'accepted unknown therapy';
  exception when sqlstate '22023' then null; end;
  begin perform public.log_search(t2, city, 'inventado'); raise exception 'accepted unknown mode';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
reset session authorization;

-- 4) COUNTERS (as owner): one row per (therapy, place, mode, day), count increments, nothing else stored
do $$
declare t2 int := current_setting('test.t2')::int; city int := current_setting('test.cordoba_city')::int; n int; c int; c_mode int;
begin
  select count(*), max(searches_count) filter (where service_mode_id is null), max(searches_count) filter (where service_mode_id is not null)
    into n, c, c_mode from public.unmet_searches where therapy_id = t2 and location_id = city;
  if n <> 2 or c <> 2 or c_mode <> 1 then raise exception 'counters: rows %, no-mode count %, mode count %', n, c, c_mode; end if;
  if exists (select 1 from public.unmet_searches where day <> (now() at time zone 'utc')::date) then raise exception 'day must be today (UTC)'; end if;
  if (select count(*) from public.unmet_searches) <> 2 then raise exception 'searches with results leaked into the counters'; end if;
end $$;

-- 5) AUTHENTICATED: therapist cannot read counters nor search; admin reads counters / el terapeuta no lee; el admin sí
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}', true);
do $$
declare t1 int := current_setting('test.t1')::int; city int := current_setting('test.cordoba_city')::int;
begin
  if (select count(*) from public.unmet_searches) <> 0 then raise exception 'a therapist sees the counters'; end if;
  begin perform * from public.search_profiles(t1, city); raise exception 'authenticated ran search_profiles';
  exception when insufficient_privilege then null; end;
  begin perform public.log_search(t1, city); raise exception 'authenticated ran log_search';
  exception when insufficient_privilege then null; end;
  begin insert into public.unmet_searches (therapy_id, location_id, day) values (1, 1, current_date); raise exception 'authenticated wrote counters';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_unmet_searches(); raise exception 'authenticated ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000001ad","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.unmet_searches) <> 2 then raise exception 'the admin cannot read the counters'; end if;
  begin update public.unmet_searches set searches_count = 5; if found then raise exception 'admin updated counters through the API'; end if;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 6) RETENTION as service_role: old rows go, recent stay; the setting rules / retención
insert into public.unmet_searches (therapy_id, location_id, service_mode_id, day) values
  (current_setting('test.t1')::int, current_setting('test.cordoba_city')::int, null, (now() at time zone 'utc')::date - 400),
  (current_setting('test.t1')::int, current_setting('test.rosario')::int, null, (now() at time zone 'utc')::date - 360);
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_unmet_searches();
  if removed <> 1 then raise exception 'purge should remove 1 row (400 days), removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.unmet_searches) <> 3 then raise exception 'purge removed the wrong rows'; end if;
  update public.app_settings set value = '1' where key = 'retention_unmet_searches_months';
  begin update public.app_settings set value = '0' where key = 'retention_unmet_searches_months'; raise exception 'retention 0 accepted';
  exception when check_violation then null; end;
  begin update public.app_settings set value = '"doce"' where key = 'retention_unmet_searches_months'; raise exception 'retention text accepted';
  exception when check_violation then null; end;
  if (select is_public from public.app_settings where key = 'retention_unmet_searches_months') then raise exception 'retention setting must be private'; end if;
end $$;

rollback;
select 'OK 13-search' as result;
