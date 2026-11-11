-- Therapist profiles: isolation, no writes, guard trigger, defense in depth.
-- Perfiles de terapeuta: aislamiento, sin escrituras, trigger de guarda, defensa en profundidad.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

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
  select '10000000-0000-0000-0000-0000000000c3'::uuid, id from public.roles where code = 'admin';

-- Two profiles created by the owner (as the server will do): A published, B unpublished.
-- Dos perfiles creados por el dueño (como hará el servidor): A publicado, B sin publicar.
insert into public.therapist_profiles (id, person_id, status_id, location_id, headline, approved_at)
  select '20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1',
         (select id from public.profile_statuses where code = 'unpublished'),
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id
            where ll.code = 'city' order by l.id limit 1),
         'Perfil de ejemplo A', now();
-- a published profile needs a phone: add it, then publish / un perfil publicado necesita teléfono: se agrega y se publica
insert into public.profile_contacts (profile_id, contact_type_id, value)
  values ('20000000-0000-0000-0000-0000000000a1', (select id from public.contact_types where code = 'phone'), '+54 351 555 0101');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id = '20000000-0000-0000-0000-0000000000a1';
insert into public.therapist_profiles (id, person_id, status_id, headline)
  select '20000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-0000000000b2',
         (select id from public.profile_statuses where code = 'unpublished'), 'Perfil de ejemplo B';
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select '20000000-0000-0000-0000-0000000000a1'::uuid, id, 60 from public.therapies order by id limit 2;
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select '20000000-0000-0000-0000-0000000000b2'::uuid, id, 45 from public.therapies order by id desc limit 1;
insert into public.profile_languages (profile_id, language_id)
  select '20000000-0000-0000-0000-0000000000a1'::uuid, id from public.languages where code = 'es';
insert into public.profile_service_modes (profile_id, service_mode_id)
  select '20000000-0000-0000-0000-0000000000a1'::uuid, id from public.service_modes;
insert into public.profile_session_formats (profile_id, session_format_id)
  select '20000000-0000-0000-0000-0000000000b2'::uuid, id from public.session_formats where code = 'individual';

-- 1) Constraints and guard trigger (as owner) / Restricciones y trigger de guarda (como dueño)
do $$
declare ok boolean;
begin
  -- base location must be a city / la ubicación base debe ser una ciudad
  ok := false;
  begin
    update public.therapist_profiles set location_id = (select id from public.locations where iso_code = 'AR')
      where id = '20000000-0000-0000-0000-0000000000b2';
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a country as base location was accepted'; end if;
  -- published needs approved_at / publicado necesita approved_at
  ok := false;
  begin
    update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
      where id = '20000000-0000-0000-0000-0000000000b2';
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a published profile without approval was accepted'; end if;
  -- one profile per person / un perfil por persona
  ok := false;
  begin
    insert into public.therapist_profiles (person_id, status_id)
      values ('10000000-0000-0000-0000-0000000000a1', (select id from public.profile_statuses where code = 'unpublished'));
  exception when unique_violation then ok := true; end;
  if not ok then raise exception 'two profiles for one person were accepted'; end if;
  -- session_minutes range / rango de minutos
  ok := false;
  begin
    update public.profile_therapies set session_minutes = 0 where profile_id = '20000000-0000-0000-0000-0000000000a1';
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'session_minutes = 0 was accepted'; end if;
end
$$;

-- 2) User A: sees only their own profile and links; cannot write.
-- 2) El usuario A: ve solo su perfil y vínculos; no escribe.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  stmt text;
  denied boolean;
begin
  if (select count(*) from public.therapist_profiles) <> 1
     or (select person_id from public.therapist_profiles) <> '10000000-0000-0000-0000-0000000000a1' then
    raise exception 'A must see exactly their own profile';
  end if;
  if (select count(*) from public.profile_therapies) <> 2 then raise exception 'A must see their 2 therapies'; end if;
  if (select count(*) from public.profile_languages) <> 1 or (select count(*) from public.profile_service_modes) <> 2 then
    raise exception 'A must see only their own languages and modes';
  end if;
  if (select count(*) from public.profile_session_formats) <> 0 then raise exception 'A must not see the formats of B'; end if;
  foreach stmt in array array[
    $q$update public.therapist_profiles set headline = 'Hackeado'$q$,
    $q$update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'suspended')$q$,
    $q$delete from public.therapist_profiles$q$,
    $q$insert into public.therapist_profiles (person_id, status_id) values (gen_random_uuid(), 1)$q$,
    $q$insert into public.profile_therapies (profile_id, therapy_id) values ('20000000-0000-0000-0000-0000000000a1', 1)$q$,
    $q$delete from public.profile_languages$q$
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

-- 3) User B: sees only theirs (mirror) / El usuario B: ve solo lo suyo (espejo)
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.therapist_profiles) <> 1
     or (select person_id from public.therapist_profiles) <> '10000000-0000-0000-0000-0000000000b2' then
    raise exception 'B must see exactly their own profile';
  end if;
  if (select count(*) from public.profile_therapies) <> 1 or (select count(*) from public.profile_session_formats) <> 1 then
    raise exception 'B must see only their own links';
  end if;
  if (select count(*) from public.profile_languages) <> 0 then raise exception 'B must not see the languages of A'; end if;
end
$$;
reset role;
reset session authorization;

-- 4) Admin C sees everything; D (logged in, no person) sees nothing.
-- 4) El admin C ve todo; D (con sesión, sin ficha) no ve nada.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.therapist_profiles) <> 2 or (select count(*) from public.profile_therapies) <> 3 then
    raise exception 'admin must see both profiles and all links';
  end if;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.therapist_profiles) <> 0 or (select count(*) from public.profile_therapies) <> 0 then
    raise exception 'a login without a person record must see nothing';
  end if;
end
$$;
reset role;
reset session authorization;

-- 5) Visitor (anon): since the public views (commit 19) anon reads a few columns of published profiles; the full
--    tables stay closed ("select *" needs every column). The exact exposure is tested in test 12.
-- 5) Visitante (anon): desde las vistas públicas (commit 19) lee pocas columnas de perfiles publicados; las tablas
--    completas siguen cerradas ("select *" exige todas las columnas). La exposición exacta se prueba en el test 12.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare
  t text;
  denied boolean;
begin
  foreach t in array array['therapist_profiles'] loop  -- the child tables expose all their columns, only for published rows (test 12)
    denied := false;
    begin execute format('select * from public.%I limit 1', t);
    exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could read all columns of %', t; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 6) Defense in depth: even with a write grant AND a permissive policy added by mistake,
--    the trigger stops an API role from changing privilege fields (rolled back at the end).
-- 6) Defensa en profundidad: aun con un permiso de escritura Y una política permisiva agregadas por error,
--    el trigger impide que un rol de la API cambie campos de privilegio (se revierte al final).
grant update on public.therapist_profiles to authenticated;
create policy __probe_update on public.therapist_profiles for update to authenticated using (true) with check (true);
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  stmt text;
  denied boolean;
begin
  -- an allowed edit still works (shows the probe is really active) / una edición permitida funciona
  update public.therapist_profiles set headline = 'Cambio permitido';
  if (select headline from public.therapist_profiles) <> 'Cambio permitido' then
    raise exception 'probe policy is not active: the test would prove nothing';
  end if;
  foreach stmt in array array[
    $q$update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'suspended')$q$,
    $q$update public.therapist_profiles set approved_at = null$q$,
    $q$update public.therapist_profiles set status_reason = 'x'$q$,
    $q$update public.therapist_profiles set person_id = '10000000-0000-0000-0000-0000000000b2'$q$
  ] loop
    denied := false;
    begin execute stmt;
    exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'trigger did not stop: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: profiles are isolated and privilege fields are guarded / perfiles aislados y campos de privilegio protegidos'
