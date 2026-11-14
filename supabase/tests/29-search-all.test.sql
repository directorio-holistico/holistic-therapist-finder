-- Search with "Todos": therapy and place are optional in search_profiles; anonymous access; invalid input still rejected.
-- Búsqueda con "Todos": terapia y lugar son opcionales en search_profiles; acceso anónimo; la entrada inválida se sigue rechazando.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000029' || k)::uuid, k || '@example.test', now() from unnest(array['a1', 'b2', 'c3']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000029' || k)::uuid, ('00000000-0000-0000-0000-0000000029' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1', 'b2', 'c3']) k;

create function pg_temp.city(p_name text) returns integer language sql as $$
  select l.id from public.locations l join public.location_translations t on t.location_id = l.id
   join public.languages g on g.id = t.language_id and g.code = 'es'
   join public.location_levels ll on ll.id = l.level_id and ll.code = 'city' where t.name = p_name $$;

-- A: Córdoba (AR), therapy 1 in person | B: Rosario (AR), therapy 1 remote | C: Barcelona (ES), therapy 2 remote
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000029' || x.k)::uuid, ('10000000-0000-0000-0000-0000000029' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - make_interval(days => x.d), pg_temp.city(x.city), x.name
  from (values ('a1', 'Córdoba', 30, 'Ana'), ('b2', 'Rosario', 20, 'Beto'), ('c3', 'Barcelona', 10, 'Cata')) x(k, city, d, name);
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000029' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+5435155509' || n
  from unnest(array['a1', 'b2', 'c3']) with ordinality as u(k, n);
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000029a1', '20000000-0000-0000-0000-0000000029b2', '20000000-0000-0000-0000-0000000029c3');

select set_config('test.t1', (select id::text from public.therapies where is_active order by id limit 1), true),
       set_config('test.t2', (select id::text from public.therapies where is_active order by id limit 1 offset 1), true),
       set_config('test.inp', (select id::text from public.service_modes where code = 'in_person'), true),
       set_config('test.rem', (select id::text from public.service_modes where code = 'remote'), true),
       set_config('test.ind', (select id::text from public.session_formats where code = 'individual'), true),
       set_config('test.ar', (select l.id::text from public.locations l join public.location_translations t on t.location_id = l.id
                               join public.location_levels ll on ll.id = l.level_id and ll.code = 'country' where t.name = 'Argentina' limit 1), true);

insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values
  ('20000000-0000-0000-0000-0000000029a1', current_setting('test.t1')::int, 60),
  ('20000000-0000-0000-0000-0000000029b2', current_setting('test.t1')::int, 60),
  ('20000000-0000-0000-0000-0000000029c3', current_setting('test.t2')::int, 60);
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id) values
  ('20000000-0000-0000-0000-0000000029a1', current_setting('test.t1')::int, current_setting('test.inp')::int),
  ('20000000-0000-0000-0000-0000000029b2', current_setting('test.t1')::int, current_setting('test.rem')::int),
  ('20000000-0000-0000-0000-0000000029c3', current_setting('test.t2')::int, current_setting('test.rem')::int);
insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id) values
  ('20000000-0000-0000-0000-0000000029a1', current_setting('test.t1')::int, current_setting('test.ind')::int),
  ('20000000-0000-0000-0000-0000000029b2', current_setting('test.t1')::int, current_setting('test.ind')::int),
  ('20000000-0000-0000-0000-0000000029c3', current_setting('test.t2')::int, current_setting('test.ind')::int);

-- as owner: the grants did not change (anon yes; authenticated, service_role and public no)
do $$
begin
  if not has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or has_function_privilege('service_role', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') then
    raise exception 'search_profiles grants changed';
  end if;
end $$;

-- as anonymous visitor / como visitante anónimo
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);

do $$
declare
  t1 int := current_setting('test.t1')::int; ar int := current_setting('test.ar')::int;
  r text; tc bigint; q text; failed int := 0;
begin
  -- no filters: the three published profiles (every group 1) / sin filtros: los tres perfiles publicados (todos grupo 1)
  select string_agg(display_name || ':' || result_group, ',' order by display_name), max(total_count) into r, tc from public.search_profiles(null, null);
  if r <> 'Ana:1,Beto:1,Cata:1' or tc <> 3 then raise exception 'no filters: got % / %', r, tc; end if;

  -- remote anywhere (any country, any therapy) / a distancia en cualquier lugar
  select string_agg(display_name, ',' order by display_name) into r from public.search_profiles(null, null, 'remote');
  if r <> 'Beto,Cata' then raise exception 'remote anywhere: got %', r; end if;

  select string_agg(display_name, ',' order by display_name) into r from public.search_profiles(null, null, 'in_person');
  if r <> 'Ana' then raise exception 'in person anywhere: got %', r; end if;

  -- one therapy, anywhere / una terapia, en cualquier lugar
  select string_agg(display_name || ':' || result_group, ',' order by display_name) into r from public.search_profiles(t1, null);
  if r <> 'Ana:1,Beto:1' then raise exception 'therapy anywhere: got %', r; end if;

  -- any therapy, one country: the remote profile from another country goes to group 3 / cualquier terapia, un país
  select string_agg(display_name || ':' || result_group, ',' order by display_name) into r from public.search_profiles(null, ar);
  if r <> 'Ana:1,Beto:1,Cata:3' then raise exception 'any therapy in a country: got %', r; end if;

  -- pagination still works / la paginación sigue andando
  select string_agg(display_name, ',') into r from public.search_profiles(null, null, null, 1, 1);
  if r is null then raise exception 'pagination with no filters returned nothing'; end if;

  -- a given therapy or place that does not exist is still rejected / lo que se da y no existe se sigue rechazando
  foreach q in array array[
    'select * from public.search_profiles(-1, null)',
    'select * from public.search_profiles(null, -1)',
    'select * from public.search_profiles(null, null, ''inventado'')',
    'select * from public.search_profiles(null, null, null, 0, 0)',
    'select * from public.search_profiles(null, null, null, 51, 0)',
    'select * from public.search_profiles(null, null, null, 20, 10001)'] loop
    begin
      execute q;
      raise exception 'accepted: %', q;
    exception when sqlstate '22023' then failed := failed + 1;
    end;
  end loop;
  if failed <> 6 then raise exception 'expected 6 rejections, got %', failed; end if;
end $$;

reset role;
reset session authorization;

-- an authenticated user and the service role still cannot call it / un usuario autenticado y service_role siguen sin poder llamarla
set session authorization authenticator;
set role authenticated;
do $$
begin
  begin perform * from public.search_profiles(null, null); raise exception 'authenticated could call search_profiles';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

rollback;
select 'OK 29-search-all' as result;
