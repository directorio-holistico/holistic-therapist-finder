-- Service modes and session formats PER THERAPY: structure, isolation (2 users + admin), anonymous access, "at least one per therapy",
-- the approval function, the public views and the search by searched therapy.
-- Modalidad y formato de sesión POR TERAPIA: estructura, aislamiento (2 usuarios + admin), acceso anónimo, "al menos uno por terapia",
-- la función de aprobación, las vistas públicas y la búsqueda por terapia buscada.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000011' || k)::uuid, k || '@example.test', now() from unnest(array['a1', 'b2', 'ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000011' || k)::uuid, ('00000000-0000-0000-0000-0000000011' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1', 'b2', 'ad']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000011ad'::uuid, id from public.roles where code = 'admin';

create function pg_temp.city(p_name text) returns integer language sql as $$
  select l.id from public.locations l join public.location_translations t on t.location_id = l.id
   join public.languages g on g.id = t.language_id and g.code = 'es'
   join public.location_levels ll on ll.id = l.level_id and ll.code = 'city' where t.name = p_name $$;

-- A: published, Córdoba. B: not published. / A: publicado, Córdoba. B: sin publicar.
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  values ('20000000-0000-0000-0000-0000000011a1', '10000000-0000-0000-0000-0000000011a1',
          (select id from public.profile_statuses where code = 'unpublished'), now() - interval '5 days', pg_temp.city('Córdoba'), 'Ana Uno'),
         ('20000000-0000-0000-0000-0000000011b2', '10000000-0000-0000-0000-0000000011b2',
          (select id from public.profile_statuses where code = 'unpublished'), null, null, 'Beto Dos');
insert into public.profile_contacts (profile_id, contact_type_id, value)
  values ('20000000-0000-0000-0000-0000000011a1', (select id from public.contact_types where code = 'phone'), '+54 351 555 0111');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id = '20000000-0000-0000-0000-0000000011a1';

select set_config('test.t1', (select id::text from public.therapies where is_active order by id limit 1), true),
       set_config('test.t2', (select id::text from public.therapies where is_active order by id limit 1 offset 1), true),
       set_config('test.t3', (select id::text from public.therapies where is_active order by id limit 1 offset 2), true),
       set_config('test.inp', (select id::text from public.service_modes where code = 'in_person'), true),
       set_config('test.rem', (select id::text from public.service_modes where code = 'remote'), true),
       set_config('test.ind', (select id::text from public.session_formats where code = 'individual'), true),
       set_config('test.grp', (select id::text from public.session_formats where code = 'group'), true),
       set_config('test.cordoba', pg_temp.city('Córdoba')::text, true);

-- A: therapy 1 = in person + remote, individual | therapy 2 = remote only, individual + group
-- B: therapy 1 = in person only, individual
insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, 60),
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t2')::int, 45),
  ('20000000-0000-0000-0000-0000000011b2', current_setting('test.t1')::int, 30);
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id) values
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, current_setting('test.inp')::int),
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, current_setting('test.rem')::int),
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t2')::int, current_setting('test.rem')::int),
  ('20000000-0000-0000-0000-0000000011b2', current_setting('test.t1')::int, current_setting('test.inp')::int);
insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id) values
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, current_setting('test.ind')::int),
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t2')::int, current_setting('test.ind')::int),
  ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t2')::int, current_setting('test.grp')::int),
  ('20000000-0000-0000-0000-0000000011b2', current_setting('test.t1')::int, current_setting('test.ind')::int);

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare t text; r text;
begin
  if to_regclass('public.profile_service_modes') is not null or to_regclass('public.profile_session_formats') is not null then
    raise exception 'the old profile-level tables must be gone';
  end if;
  foreach t in array array['profile_therapy_service_modes', 'profile_therapy_session_formats'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) then raise exception '% has no RLS', t; end if;
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if has_table_privilege(r, 'public.' || t, 'INSERT') or has_table_privilege(r, 'public.' || t, 'UPDATE')
         or has_table_privilege(r, 'public.' || t, 'DELETE') or has_table_privilege(r, 'public.' || t, 'TRUNCATE') then
        raise exception '% must not write %', r, t;
      end if;
    end loop;
    if has_table_privilege('service_role', 'public.' || t, 'SELECT') then raise exception 'service_role must not read %', t; end if;
  end loop;
  if has_function_privilege('anon', 'public.profile_therapy_options_check()', 'execute')
     or has_function_privilege('authenticated', 'public.profile_therapy_options_check()', 'execute') then
    raise exception 'the check function must be closed to API roles';
  end if;
end $$;

-- 2) ISOLATION: A, B and the administrator / AISLAMIENTO
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000011a1","role":"authenticated"}', true);
do $$
declare stmt text; denied boolean;
begin
  if (select count(*) from public.profile_therapy_service_modes) <> 3 or (select count(*) from public.profile_therapy_session_formats) <> 3 then
    raise exception 'A must see exactly their own 3 modes and 3 formats';
  end if;
  if exists (select 1 from public.profile_therapy_service_modes where profile_id <> '20000000-0000-0000-0000-0000000011a1') then
    raise exception 'A sees rows of B';
  end if;
  foreach stmt in array array[
    $q$insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id) values ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, current_setting('test.inp')::int)$q$,
    $q$update public.profile_therapy_service_modes set service_mode_id = service_mode_id$q$,
    $q$delete from public.profile_therapy_service_modes$q$,
    $q$insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id) values ('20000000-0000-0000-0000-0000000011a1', current_setting('test.t1')::int, current_setting('test.grp')::int)$q$,
    $q$update public.profile_therapy_session_formats set session_format_id = session_format_id$q$,
    $q$delete from public.profile_therapy_session_formats$q$] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'A could run: %', stmt; end if;
  end loop;
end $$;
reset role;
reset session authorization;

set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000011b2","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.profile_therapy_service_modes) <> 1 or (select count(*) from public.profile_therapy_session_formats) <> 1 then
    raise exception 'B must see exactly their own 1 mode and 1 format';
  end if;
  if exists (select 1 from public.profile_therapy_service_modes where profile_id = '20000000-0000-0000-0000-0000000011a1') then
    raise exception 'B sees rows of A';
  end if;
end $$;
reset role;
reset session authorization;

set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000011ad","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.profile_therapy_service_modes) <> 4 or (select count(*) from public.profile_therapy_session_formats) <> 4 then
    raise exception 'the administrator must see all 4 modes and 4 formats';
  end if;
end $$;
reset role;
reset session authorization;

-- 3) ANONYMOUS: only published profiles, only the written columns, no writes / ANÓNIMO
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare stmt text; denied boolean;
begin
  if (select count(*) from public.profile_therapy_service_modes) <> 3 or (select count(*) from public.profile_therapy_session_formats) <> 3 then
    raise exception 'anon must see only the 3 modes and 3 formats of the published profile';
  end if;
  if exists (select 1 from public.profile_therapy_service_modes where profile_id = '20000000-0000-0000-0000-0000000011b2') then
    raise exception 'anon sees the modes of an unpublished profile';
  end if;
  foreach stmt in array array[
    $q$insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id) values (gen_random_uuid(), 1, 1)$q$,
    $q$update public.profile_therapy_service_modes set service_mode_id = service_mode_id$q$,
    $q$delete from public.profile_therapy_service_modes$q$,
    $q$insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id) values (gen_random_uuid(), 1, 1)$q$,
    $q$update public.profile_therapy_session_formats set session_format_id = session_format_id$q$,
    $q$delete from public.profile_therapy_session_formats$q$] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end $$;

-- 4) THE VIEWS: the card shows the UNION, the detail shows each therapy with its own lists / LAS VISTAS
do $$
declare c public.public_profile_cards%rowtype; d jsonb; x jsonb;
begin
  select * into c from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000011a1';
  if c.service_modes <> array['in_person', 'remote'] then raise exception 'card modes must be the union, got %', c.service_modes; end if;
  if c.session_formats <> array['individual', 'group'] then raise exception 'card formats must be the union, got %', c.session_formats; end if;
  select therapies_detail into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000011a1';
  select e into x from jsonb_array_elements(d) e where (e ->> 'therapy_id')::int = current_setting('test.t1')::int;
  if x -> 'service_modes' <> '["in_person", "remote"]'::jsonb or x -> 'session_formats' <> '["individual"]'::jsonb then
    raise exception 'therapy 1 detail wrong: %', x;
  end if;
  select e into x from jsonb_array_elements(d) e where (e ->> 'therapy_id')::int = current_setting('test.t2')::int;
  if x -> 'service_modes' <> '["remote"]'::jsonb or x -> 'session_formats' <> '["individual", "group"]'::jsonb then
    raise exception 'therapy 2 detail wrong: %', x;
  end if;
end $$;

-- 5) THE SEARCH looks only at the modes of the SEARCHED therapy / LA BÚSQUEDA mira solo las modalidades de la terapia BUSCADA
do $$
declare city int := current_setting('test.cordoba')::int;
begin
  -- A offers in person only for therapy 1: searching therapy 2 in person must NOT find A, although the card says "in person"
  if exists (select 1 from public.search_profiles(current_setting('test.t2')::int, city, 'in_person', 20, 0)) then
    raise exception 'therapy 2 is remote only: it must not match an in person search';
  end if;
  if not exists (select 1 from public.search_profiles(current_setting('test.t2')::int, city, 'remote', 20, 0)
                 where profile_id = '20000000-0000-0000-0000-0000000011a1') then
    raise exception 'therapy 2 remote must find A';
  end if;
  if not exists (select 1 from public.search_profiles(current_setting('test.t1')::int, city, 'in_person', 20, 0)
                 where profile_id = '20000000-0000-0000-0000-0000000011a1') then
    raise exception 'therapy 1 in person must find A';
  end if;
  if not exists (select 1 from public.search_profiles(current_setting('test.t2')::int, city, null, 20, 0)
                 where profile_id = '20000000-0000-0000-0000-0000000011a1') then
    raise exception 'a search without a mode must find A';
  end if;
end $$;
reset role;
reset session authorization;

-- 6) "AT LEAST ONE MODE AND ONE FORMAT PER THERAPY" (deferred check, forced here) / "AL MENOS UNA MODALIDAD Y UN FORMATO POR TERAPIA"
do $$
declare ok boolean; a uuid := '20000000-0000-0000-0000-0000000011a1';
begin
  -- a therapy with nothing / una terapia sin nada
  ok := false;
  begin
    insert into public.profile_therapies (profile_id, therapy_id) values (a, current_setting('test.t3')::int);
    set constraints all immediate;
  exception when check_violation then ok := true;
  end;
  if not ok then raise exception 'a therapy without modes must be refused'; end if;
  set constraints all deferred;

  -- a mode but no format / una modalidad pero ningún formato
  ok := false;
  begin
    insert into public.profile_therapies (profile_id, therapy_id) values (a, current_setting('test.t3')::int);
    insert into public.profile_therapy_service_modes values (a, current_setting('test.t3')::int, current_setting('test.rem')::int);
    set constraints all immediate;
  exception when check_violation then ok := true;
  end;
  if not ok then raise exception 'a therapy without formats must be refused'; end if;
  set constraints all deferred;

  -- complete: accepted / completa: se acepta
  insert into public.profile_therapies (profile_id, therapy_id) values (a, current_setting('test.t3')::int);
  insert into public.profile_therapy_service_modes values (a, current_setting('test.t3')::int, current_setting('test.rem')::int);
  insert into public.profile_therapy_session_formats values (a, current_setting('test.t3')::int, current_setting('test.ind')::int);
  set constraints all immediate;
  set constraints all deferred;

  -- removing the LAST mode is refused; removing one of two is fine; removing the therapy takes its children with it
  ok := false;
  begin
    delete from public.profile_therapy_service_modes where profile_id = a and therapy_id = current_setting('test.t3')::int;
    set constraints all immediate;
  exception when check_violation then ok := true;
  end;
  if not ok then raise exception 'removing the last mode must be refused'; end if;
  set constraints all deferred;

  delete from public.profile_therapy_service_modes
   where profile_id = a and therapy_id = current_setting('test.t1')::int and service_mode_id = current_setting('test.inp')::int;
  set constraints all immediate;
  set constraints all deferred;

  delete from public.profile_therapies where profile_id = a and therapy_id = current_setting('test.t3')::int;
  set constraints all immediate;
  if exists (select 1 from public.profile_therapy_service_modes where profile_id = a and therapy_id = current_setting('test.t3')::int) then
    raise exception 'the children of a removed therapy must go with it';
  end if;
  set constraints all deferred;
end $$;

-- 7) APPROVAL: the payload carries the lists INSIDE each therapy, and a new approval replaces them / LA APROBACIÓN
do $$
declare b uuid := '20000000-0000-0000-0000-0000000011b2';
begin
  perform public.apply_revision_payload(b, jsonb_build_object('therapies', jsonb_build_array(
    jsonb_build_object('therapy_id', current_setting('test.t1')::int,
      'service_modes', jsonb_build_array(current_setting('test.rem')::int), 'session_formats', jsonb_build_array(current_setting('test.grp')::int)),
    jsonb_build_object('therapy_id', current_setting('test.t2')::int,
      'service_modes', jsonb_build_array(current_setting('test.inp')::int, current_setting('test.rem')::int),
      'session_formats', jsonb_build_array(current_setting('test.ind')::int, current_setting('test.ind')::int)))));
  set constraints all immediate;
  if (select count(*) from public.profile_therapy_service_modes where profile_id = b) <> 3
     or (select count(*) from public.profile_therapy_session_formats where profile_id = b) <> 2 then
    raise exception 'the lists of each therapy were not applied (a repeated id must count once)';
  end if;
  if not exists (select 1 from public.profile_therapy_service_modes where profile_id = b and therapy_id = current_setting('test.t1')::int
                 and service_mode_id = current_setting('test.rem')::int) then
    raise exception 'therapy 1 must now be remote';
  end if;
  set constraints all deferred;  -- the real default: checked at the end of the transaction / el valor real: se revisa al final
  -- a second approval with only therapy 2 removes therapy 1 and its lists / un segundo payload solo con la terapia 2 saca la 1
  perform public.apply_revision_payload(b, jsonb_build_object('therapies', jsonb_build_array(
    jsonb_build_object('therapy_id', current_setting('test.t2')::int,
      'service_modes', jsonb_build_array(current_setting('test.inp')::int), 'session_formats', jsonb_build_array(current_setting('test.grp')::int)))));
  set constraints all immediate;
  if (select count(*) from public.profile_therapy_service_modes where profile_id = b) <> 1
     or exists (select 1 from public.profile_therapy_service_modes where profile_id = b and therapy_id = current_setting('test.t1')::int) then
    raise exception 'a removed therapy must take its modes with it';
  end if;
  set constraints all deferred;
end $$;

rollback;
select 'OK 28-modes-formats-per-therapy' as result;
