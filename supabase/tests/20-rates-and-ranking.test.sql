-- Rates freshness, direct rate changes, owner pin and result order. Includes the 2-user isolation checks.
-- Frescura de tarifas, cambio directo de tarifas, perfil fijado y orden de resultados. Incluye aislamiento con 2 usuarios.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000007' || k)::uuid, 'r' || k || '@example.test', now()
  from unnest(array['a1','a2','a3','a4','ad','c1','c2','c3','c4','c5','c6','c7']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000007' || k)::uuid, ('00000000-0000-0000-0000-0000000007' || k)::uuid, 'Persona ' || k, 'r' || k || '@example.test'
  from unnest(array['a1','a2','a3','a4','ad','c1','c2','c3','c4','c5','c6','c7']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000007ad'::uuid, id from public.roles where code = 'admin';

create function pg_temp.city(p_name text) returns integer language sql as $$
  select l.id from public.locations l join public.location_translations t on t.location_id = l.id
   join public.languages g on g.id = t.language_id and g.code = 'es'
   join public.location_levels ll on ll.id = l.level_id and ll.code = 'city' where t.name = p_name $$;

-- Profiles: a1 (T1+T2) a2 (T1) published | a3 unpublished | a4 person without profile | c1..c7 ranking fixtures
-- Perfiles: a1 (T1+T2) a2 (T1) publicados | a3 sin publicar | a4 persona sin perfil | c1..c7 para el orden
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000007' || x.k)::uuid, ('10000000-0000-0000-0000-0000000007' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - make_interval(days => x.d),
         pg_temp.city('Córdoba'), x.name
  from (values ('a1', 60, 'Alfa'), ('a2', 61, 'Beta'), ('a3', 62, 'Gamma'),
               ('c1', 10, 'Pin'), ('c2', 20, 'FreshPhoto'), ('c3', 40, 'FreshNoPhoto'), ('c4', 30, 'StalePhoto'),
               ('c5', 25, 'NoPricePhoto'), ('c6', 15, 'NoPriceNoPhoto'), ('c7', 35, 'Fresh4m')) x(k, d, name);
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000007' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+5435155507' || n
  from unnest(array['a1','a2','a3','c1','c2','c3','c4','c5','c6','c7']) with ordinality as u(k, n);
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select ('20000000-0000-0000-0000-0000000007' || k)::uuid, (select id from public.therapies where is_active order by id limit 1), 60
  from unnest(array['a1','a2','a3','c1','c2','c3','c4','c5','c6','c7']) k;
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  values ('20000000-0000-0000-0000-0000000007a1', (select id from public.therapies where is_active order by id limit 1 offset 1), 60);
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
  select ('20000000-0000-0000-0000-0000000007' || k)::uuid, (select id from public.therapies where is_active order by id limit 1),
         (select id from public.service_modes where code = 'in_person')
  from unnest(array['a1','a2','a3','c1','c2','c3','c4','c5','c6','c7']) k;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in (select ('20000000-0000-0000-0000-0000000007' || k)::uuid from unnest(array['a1','a2','c1','c2','c3','c4','c5','c6','c7']) k);
update public.therapist_profiles set photo_path = 'x/' || id::text || '.jpg'
  where id in (select ('20000000-0000-0000-0000-0000000007' || k)::uuid from unnest(array['c2','c4','c5']) k);
-- rates of the ranking fixtures (as owner) / tarifas de los perfiles de orden (como dueño)
insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id)
  select ('20000000-0000-0000-0000-0000000007' || k)::uuid, (select id from public.therapies where is_active order by id limit 1),
         (select id from public.rate_audiences where is_active order by id limit 1), 1000, (select id from public.currencies where code = 'ARS')
  from unnest(array['c2','c3','c4','c7']) k;
update public.therapist_profiles set rates_confirmed_at = now() - interval '1 day'   where id = '20000000-0000-0000-0000-0000000007c2';
update public.therapist_profiles set rates_confirmed_at = now() - interval '10 days' where id = '20000000-0000-0000-0000-0000000007c3';
update public.therapist_profiles set rates_confirmed_at = now() - interval '7 months' where id = '20000000-0000-0000-0000-0000000007c4';
update public.therapist_profiles set rates_confirmed_at = now() - interval '4 months' where id = '20000000-0000-0000-0000-0000000007c7';
update public.therapist_profiles set is_pinned = true where id = '20000000-0000-0000-0000-0000000007c1';

select set_config('test.t1', (select id::text from public.therapies where is_active order by id limit 1), true),
       set_config('test.t2', (select id::text from public.therapies where is_active order by id limit 1 offset 1), true),
       set_config('test.t3', (select id::text from public.therapies where is_active order by id limit 1 offset 2), true),
       set_config('test.aud', (select id::text from public.rate_audiences where is_active order by id limit 1), true),
       set_config('test.ars', (select id::text from public.currencies where code = 'ARS'), true),
       set_config('test.cordoba', pg_temp.city('Córdoba')::text, true);

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
begin
  if not (select prosecdef from pg_proc where oid = 'public.update_my_rates(jsonb)'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.confirm_my_rates()'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.set_profile_pinned(uuid,boolean)'::regprocedure) then
    raise exception 'the three new functions must be SECURITY DEFINER';
  end if;
  if has_function_privilege('anon', 'public.update_my_rates(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.confirm_my_rates()', 'execute')
     or has_function_privilege('anon', 'public.set_profile_pinned(uuid,boolean)', 'execute')
     or has_function_privilege('service_role', 'public.update_my_rates(jsonb)', 'execute')
     or has_function_privilege('service_role', 'public.set_profile_pinned(uuid,boolean)', 'execute') then
    raise exception 'anon and service_role must not execute the new functions';
  end if;
  if not has_function_privilege('authenticated', 'public.update_my_rates(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.confirm_my_rates()', 'execute')
     or not has_function_privilege('authenticated', 'public.set_profile_pinned(uuid,boolean)', 'execute') then
    raise exception 'authenticated must execute the new functions';
  end if;
  if not has_function_privilege('anon', 'public.rates_validity_months()', 'execute') then
    raise exception 'anon must execute rates_validity_months';
  end if;
  if public.rates_validity_months() <> 6 then raise exception 'the default validity must be 6 months'; end if;
  begin
    update public.app_settings set value = '0'::jsonb where key = 'rates_validity_months';
    raise exception 'validity 0 must be refused';
  exception when check_violation then null;
  end;
  begin
    update public.app_settings set value = '37'::jsonb where key = 'rates_validity_months';
    raise exception 'validity 37 must be refused';
  exception when check_violation then null;
  end;
end $$;

-- 2) THE VISITOR (anon): new columns visible, private ones still hidden / EL VISITANTE
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare ok boolean; names text;
begin
  if (select count(*) from public.public_profile_cards where rates_current) <> 3 then
    raise exception 'anon must see exactly 3 profiles with current rates (c2, c3 and c7)';
  end if;
  if not (select is_pinned from public.public_profile_cards where display_name = 'Pin') then raise exception 'the pin is not visible'; end if;
  perform is_pinned, rates_confirmed_at from public.therapist_profiles;       -- allowed columns
  ok := false;
  begin perform person_id from public.therapist_profiles; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'anon must not read person_id'; end if;
  ok := false;
  begin perform public.update_my_rates('[]'::jsonb); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'anon must not call update_my_rates'; end if;
  ok := false;
  begin perform public.confirm_my_rates(); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'anon must not call confirm_my_rates'; end if;
  ok := false;
  begin perform public.set_profile_pinned('20000000-0000-0000-0000-0000000007c2'::uuid, true); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'anon must not call set_profile_pinned'; end if;

  -- RANKING inside the group: pin, current rates, photo, oldest approval / ORDEN dentro del grupo
  select string_agg(r.display_name, ',' order by r.ordinality) into names
    from public.search_profiles(current_setting('test.t1')::int, current_setting('test.cordoba')::int, null, 50, 0) with ordinality r
    where r.display_name not in ('Alfa', 'Beta');
  if names is distinct from 'Pin,FreshPhoto,FreshNoPhoto,Fresh4m,StalePhoto,NoPricePhoto,NoPriceNoPhoto' then
    raise exception 'unexpected order: %', names;
  end if;
end $$;
reset role;
reset session authorization;

-- configurable validity: with 3 months, the 4-month confirmation is no longer current / vigencia configurable
update public.app_settings set value = '3'::jsonb where key = 'rates_validity_months';
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare names text;
begin
  select string_agg(r.display_name, ',' order by r.ordinality) into names
    from public.search_profiles(current_setting('test.t1')::int, current_setting('test.cordoba')::int, null, 50, 0) with ordinality r
    where r.display_name not in ('Alfa', 'Beta');
  if names is distinct from 'Pin,FreshPhoto,FreshNoPhoto,StalePhoto,NoPricePhoto,Fresh4m,NoPriceNoPhoto' then
    raise exception 'unexpected order with 3 months: %', names;
  end if;
end $$;
reset role;
reset session authorization;
update public.app_settings set value = '6'::jsonb where key = 'rates_validity_months';

-- 3) THERAPIST A1: changes own rates with no moderation / A1 cambia sus tarifas sin moderación
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a1","role":"authenticated"}', true);
do $$
declare ok boolean; t1 text := current_setting('test.t1'); t2 text := current_setting('test.t2'); t3 text := current_setting('test.t3');
        aud text := current_setting('test.aud'); ars text := current_setting('test.ars'); good jsonb;
begin
  good := ('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":1500,"currency_id":' || ars || '}]')::jsonb;
  if (select rates_confirmed_at from public.therapist_profiles) is not null then raise exception 'a1 starts with no confirmation'; end if;
  ok := false;
  begin perform public.confirm_my_rates(); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'confirming with no rates must be refused'; end if;

  perform public.update_my_rates(good);
  if (select count(*) from public.profile_therapy_rates) <> 1 then raise exception 'a1 must see exactly its own rate'; end if;
  if (select rates_confirmed_at from public.therapist_profiles) is null then raise exception 'update_my_rates must set the confirmation date'; end if;

  -- refused inputs; the previous rates must survive each failure / entradas rechazadas; las tarifas previas sobreviven
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t3 || ',"rate_audience_id":' || aud || ',"amount":10,"currency_id":' || ars || '}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a therapy outside the profile must be refused'; end if;
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":-5,"currency_id":' || ars || '}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a negative amount must be refused'; end if;
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":10,"currency_id":99999}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an unknown currency must be refused'; end if;
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":10,"currency_id":' || ars || ',"extra":1}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an unknown key must be refused'; end if;
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":1.234,"currency_id":' || ars || '}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'too many decimals for the currency must be refused'; end if;
  ok := false; begin perform public.update_my_rates(good || good); exception when sqlstate '23505' then ok := true; end;
  if not ok then raise exception 'the same therapy and audience twice must be refused'; end if;
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || t1 || ',"rate_audience_id":' || aud || ',"amount":10.5,"currency_id":' || (select id::text from public.currencies where code = 'CLP') || '}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'cents in a currency with no decimals (CLP) must be refused'; end if;
  ok := false; begin perform public.update_my_rates('{"a":1}'::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a non-list must be refused'; end if;
  if (select amount from public.profile_therapy_rates) <> 1500 then raise exception 'a failed call must leave the rates untouched'; end if;

  perform public.confirm_my_rates();   -- now it has a rate / ahora sí tiene una tarifa
  -- the therapist cannot write the privilege fields, not even directly / no puede escribir los campos de privilegio
  ok := false; begin update public.therapist_profiles set is_pinned = true; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist must not pin itself'; end if;
  ok := false; begin update public.therapist_profiles set rates_confirmed_at = now() + interval '5 years'; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist must not write the confirmation date directly'; end if;
  ok := false; begin perform public.set_profile_pinned('20000000-0000-0000-0000-0000000007a1'::uuid, true); exception when sqlstate '42501' then ok := true; end;
  if not ok then raise exception 'a non-admin must not call set_profile_pinned'; end if;
end $$;
reset role;
reset session authorization;

-- A1 did not touch A2 (isolation) / A1 no tocó a A2 (aislamiento)
do $$
begin
  if exists (select 1 from public.profile_therapy_rates where profile_id = '20000000-0000-0000-0000-0000000007a2') then
    raise exception 'a1 changed the rates of a2';
  end if;
  if (select rates_confirmed_at from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000007a2') is not null then
    raise exception 'a1 changed the confirmation of a2';
  end if;
end $$;

-- 4) THERAPIST A2: only its own profile; a profile that is not published or does not exist is refused
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a2","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  perform public.update_my_rates(('[{"therapy_id":' || current_setting('test.t1') || ',"rate_audience_id":' || current_setting('test.aud') || ',"amount":900,"currency_id":' || current_setting('test.ars') || '}]')::jsonb);
  if (select count(*) from public.profile_therapy_rates) <> 1 or (select amount from public.profile_therapy_rates) <> 900 then
    raise exception 'a2 must see only its own rate';
  end if;
  -- a2 has T1 only: T2 belongs to a1's profile, not to a2's / a2 solo tiene T1: T2 es del perfil de a1
  ok := false; begin perform public.update_my_rates(('[{"therapy_id":' || current_setting('test.t2') || ',"rate_audience_id":' || current_setting('test.aud') || ',"amount":1,"currency_id":' || current_setting('test.ars') || '}]')::jsonb); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a2 must not set rates for a therapy it does not have'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select amount from public.profile_therapy_rates where profile_id = '20000000-0000-0000-0000-0000000007a1') <> 1500 then
    raise exception 'a2 changed the rates of a1';
  end if;
end $$;

set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a3","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  ok := false; begin perform public.update_my_rates('[]'::jsonb); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'an unpublished profile must use a revision'; end if;
  ok := false; begin perform public.confirm_my_rates(); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'an unpublished profile cannot confirm rates'; end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a4","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  ok := false; begin perform public.update_my_rates('[]'::jsonb); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'a person with no profile must be refused';  end if;
end $$;
reset role;
reset session authorization;

-- 5) ADMIN: only an admin pins; the guard also stops API roles even if an update grant appeared by mistake
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007ad","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  perform public.set_profile_pinned('20000000-0000-0000-0000-0000000007c2'::uuid, true);
  perform public.set_profile_pinned('20000000-0000-0000-0000-0000000007c2'::uuid, false);
  ok := false; begin perform public.set_profile_pinned('20000000-0000-0000-0000-000000000999'::uuid, true); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'pinning a missing profile must fail'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select is_pinned from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000007c2') then raise exception 'unpin did not work'; end if;
  if (select count(*) from public.audit_log where table_name = 'therapist_profiles' and row_key = '20000000-0000-0000-0000-0000000007c2') < 1 then
    raise exception 'the pin change must be audited';
  end if;
end $$;

grant update on public.therapist_profiles to authenticated;
create policy tmp_profiles_update on public.therapist_profiles for update to authenticated using (true) with check (true);
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a1","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  ok := false; begin update public.therapist_profiles set is_pinned = true where id = '20000000-0000-0000-0000-0000000007a1'; exception when sqlstate '42501' then ok := true; end;
  if not ok then raise exception 'the guard must stop an API role from changing is_pinned';  end if;
  ok := false; begin update public.therapist_profiles set rates_confirmed_at = now() + interval '1 day' where id = '20000000-0000-0000-0000-0000000007a1'; exception when sqlstate '42501' then ok := true; end;
  if not ok then raise exception 'the guard must stop an API role from changing rates_confirmed_at'; end if;
end $$;
reset role;
reset session authorization;

-- 6) Approving a revision that carries therapies confirms the rates; one without therapies does not
do $$
declare p uuid := '20000000-0000-0000-0000-0000000007a3';
begin
  perform public.apply_revision_payload(p, '{"headline":"Hola"}'::jsonb);
  if (select rates_confirmed_at from public.therapist_profiles where id = p) is not null then
    raise exception 'a payload without therapies must not confirm rates';
  end if;
  perform public.apply_revision_payload(p, ('{"therapies":[{"therapy_id":' || current_setting('test.t1')
    || ',"service_modes":[' || (select id from public.service_modes where code = 'in_person')
    || '],"session_formats":[' || (select id from public.session_formats where code = 'individual')
    || '],"rates":[{"rate_audience_id":' || current_setting('test.aud') || ',"amount":700,"currency_id":' || current_setting('test.ars') || '}]}]}')::jsonb);
  if (select rates_confirmed_at from public.therapist_profiles where id = p) is null then
    raise exception 'a payload with therapies must confirm the rates';
  end if;
end $$;

rollback;
\echo 'OK: rates freshness, direct rate changes, owner pin and ranking behave as designed / frescura de tarifas, cambio directo, fijado y orden segun el diseno'
