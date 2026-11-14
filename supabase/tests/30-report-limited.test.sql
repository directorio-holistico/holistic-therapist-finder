-- Report a profile behind the origin limit (commit 70, ADR-0003): the only door, the count, isolation, error code, roles.
-- Denunciar un perfil detrás del límite por origen (commit 70, ADR-0003): la única puerta, el conteo, el aislamiento,
-- el código de error y los roles. Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000030' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000030' || k)::uuid, ('00000000-0000-0000-0000-0000000030' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2']) k;
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000030' || k)::uuid, ('10000000-0000-0000-0000-0000000030' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '10 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1), 'Perfil ' || k
  from unnest(array['a1','a2']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select '20000000-0000-0000-0000-0000000030a1'::uuid, ct.id, '+54 351 555 0030', false from public.contact_types ct where ct.code = 'phone';
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id = '20000000-0000-0000-0000-0000000030a1';
-- a2 stays unpublished: it cannot be reported / a2 queda no publicado: no se puede denunciar

-- 1) STRUCTURE AND SETTING (as owner) / ESTRUCTURA Y AJUSTE
do $$
declare f text; v text;
begin
  f := 'public.report_profile_limited(uuid, text, text, text, text)';
  if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% must be SECURITY DEFINER', f; end if;
  if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=pg_catalog, public']) then
    raise exception '% needs a fixed search_path', f; end if;
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or not has_function_privilege('service_role', f, 'execute') then
    raise exception '% must be executable by service_role only', f; end if;
  f := 'public.report_profile(uuid, text, text, text)';
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception 'the direct door report_profile must be closed to every API role'; end if;
  if (select value::text from public.app_settings where key = 'report_daily_limit') <> '5' then raise exception 'default limit must be 5'; end if;
  if (select is_public from public.app_settings where key = 'report_daily_limit') then raise exception 'report_daily_limit must be private'; end if;
  foreach v in array array['0', '1001', '-1', '2.5', '"cinco"', 'true', 'null', '100000'] loop
    begin update public.app_settings set value = v::jsonb where key = 'report_daily_limit'; raise exception 'limit % accepted', v;
    exception when check_violation then null; end;
  end loop;
  update public.app_settings set value = '1000' where key = 'report_daily_limit';   -- upper edge ok / borde superior ok
  update public.app_settings set value = '1' where key = 'report_daily_limit';       -- lower edge ok / borde inferior ok
  update public.app_settings set value = '5' where key = 'report_daily_limit';
end $$;

-- 2) THE DOOR AS service_role: limit, isolation, error code / LA PUERTA COMO service_role
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
declare
  a1 uuid := '20000000-0000-0000-0000-0000000030a1'; a2 uuid := '20000000-0000-0000-0000-0000000030a2';
  h1 text := repeat('1', 64); h2 text := repeat('2', 64); h3 text := repeat('3', 64);
  i int; blocked boolean; msg text; bad text; id bigint; q text; failed int := 0;
begin
  -- the direct door is closed / la puerta directa está cerrada
  begin perform public.report_profile(a1, 'other'); raise exception 'service_role called report_profile directly';
  exception when insufficient_privilege then null; end;
  -- five allowed from origin 1; each returns an id / cinco permitidas del origen 1; cada una devuelve un id
  for i in 1..5 loop
    id := public.report_profile_limited(a1, 'cure_claim', '  Promete curar  ', ' Ana@Example.TEST ', h1);
    if id is null then raise exception 'report % of origin 1 returned no id', i; end if;
  end loop;
  -- the sixth is blocked with RL429 and creates nothing / la sexta se bloquea con RL429 y no crea nada
  blocked := false;
  begin perform public.report_profile_limited(a1, 'other', null, null, h1);
  exception when sqlstate 'RL429' then blocked := true; get stacked diagnostics msg = message_text; end;
  if not blocked then raise exception 'the 6th report of origin 1 was not blocked'; end if;
  if msg <> 'rate limit reached' then raise exception 'unexpected message: %', msg; end if;
  -- another origin is not affected / otro origen no se afecta
  perform public.report_profile_limited(a1, 'other', null, null, h2);
  -- invalid reports fail with 22023 and are NOT counted (origin 3 can still use all 5) / las inválidas fallan y NO se cuentan
  foreach q in array array[
    $q$select public.report_profile_limited(null, 'other', null, null, repeat('3', 64))$q$,
    $q$select public.report_profile_limited('99999999-9999-9999-9999-999999999999', 'other', null, null, repeat('3', 64))$q$,
    $q$select public.report_profile_limited('20000000-0000-0000-0000-0000000030a2', 'other', null, null, repeat('3', 64))$q$,
    $q$select public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'inventado', null, null, repeat('3', 64))$q$,
    $q$select public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', repeat('x', 1001), null, repeat('3', 64))$q$,
    $q$select public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, 'sin-arroba', repeat('3', 64))$q$] loop
    begin execute q; raise exception 'accepted: %', q;
    exception when sqlstate '22023' then failed := failed + 1; end;
  end loop;
  if failed <> 6 then raise exception 'expected 6 rejections, got %', failed; end if;
  for i in 1..5 loop perform public.report_profile_limited(a1, 'false_information', null, null, h3); end loop;
  begin perform public.report_profile_limited(a1, 'other', null, null, h3); raise exception 'origin 3 passed 5';
  exception when sqlstate 'RL429' then null; end;
  -- invalid hashes: 22023, nothing stored / hashes inválidos: 22023, no se guarda nada
  foreach bad in array array[repeat('A', 64), repeat('1', 63), repeat('1', 65), '203.0.113.7', '2001:db8::1', '', repeat('g', 64)] loop
    begin perform public.report_profile_limited(a1, 'other', null, null, bad); raise exception 'hash [%] accepted', bad;
    exception when sqlstate '22023' then null; end;
  end loop;
  begin perform public.report_profile_limited(a1, 'other', null, null, null); raise exception 'null hash accepted';
  exception when sqlstate '22023' then null; end;
  -- reports and reveals do not share slots: origin 1 is out of reports but can still reveal
  -- denuncias y revelados no comparten lugares: el origen 1 no tiene denuncias pero sí puede revelar
  perform * from public.reveal_contact_limited(a1, h1);
end $$;
reset role;
reset session authorization;

-- 2b) WHAT WAS STORED (as owner) / LO QUE SE GUARDÓ
do $$
begin
  if (select hits from public.rate_limit_hits where action = 'report' and origin_hash = repeat('1', 64)) <> 5
     or (select hits from public.rate_limit_hits where action = 'report' and origin_hash = repeat('2', 64)) <> 1
     or (select hits from public.rate_limit_hits where action = 'report' and origin_hash = repeat('3', 64)) <> 5
     or (select count(*) from public.rate_limit_hits where action = 'report') <> 3 then
    raise exception 'report counters should be 5, 1, 5 (invalid reports and blocked calls store nothing)'; end if;
  if (select hits from public.rate_limit_hits where action = 'reveal' and origin_hash = repeat('1', 64)) <> 1 then
    raise exception 'the reveal counter of origin 1 should be separate and equal to 1'; end if;
  if (select count(*) from public.reports) <> 11 then raise exception 'expected 11 reports, got %', (select count(*) from public.reports); end if;
  if exists (select 1 from public.reports r join public.report_statuses s on s.id = r.status_id where s.code <> 'open') then raise exception 'new reports must be open'; end if;
  if (select count(*) from public.reports where details = 'Promete curar' and reporter_email = 'ana@example.test') <> 5 then
    raise exception 'details and email must be trimmed, email lower case'; end if;
end $$;

-- 3) THE LIMIT IS A SETTING; A MISSING SETTING CLOSES THE DOOR / EL LÍMITE ES UN AJUSTE; SIN AJUSTE SE CIERRA LA PUERTA
update public.app_settings set value = '2' where key = 'report_daily_limit';
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
begin
  -- lowering below the count blocks at once (origin 1 has 5) / bajar el límite por debajo de lo contado bloquea de inmediato
  begin perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('1', 64)); raise exception 'lowered limit ignored';
  exception when sqlstate 'RL429' then null; end;
  -- origin 2 had 1: one more passes, the next does not / el origen 2 tenía 1: pasa uno más, el siguiente no
  perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('2', 64));
  begin perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('2', 64)); raise exception 'origin 2 passed 2';
  exception when sqlstate 'RL429' then null; end;
end $$;
reset role;
reset session authorization;
delete from public.app_settings where key = 'report_daily_limit';
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('8', 64)); raise exception 'reported without the limit setting';
  exception when check_violation then null; end;
end $$;
reset role;
reset session authorization;
insert into public.app_settings (key, value, is_public, description) values ('report_daily_limit', '5', false, 'restored');

-- 4) NO OTHER ROLE (anon, authenticated, even the owner of the profile) / NINGÚN OTRO ROL
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('9', 64)); raise exception 'anon reported';
  exception when insufficient_privilege then null; end;
  begin perform public.report_profile('20000000-0000-0000-0000-0000000030a1', 'other'); raise exception 'anon called report_profile';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'anon read the counters';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000030a1","role":"authenticated"}', true);
do $$
begin
  begin perform public.report_profile_limited('20000000-0000-0000-0000-0000000030a1', 'other', null, null, repeat('9', 64)); raise exception 'authenticated reported';
  exception when insufficient_privilege then null; end;
  begin perform public.report_profile('20000000-0000-0000-0000-0000000030a1', 'other'); raise exception 'authenticated called report_profile';
  exception when insufficient_privilege then null; end;
  if (select count(*) from public.reports) <> 0 then raise exception 'a therapist sees reports'; end if;
end $$;
reset role;
reset session authorization;

-- 5) THE PURGE ALSO COVERS THE NEW ACTION / LA PURGA CUBRE TAMBIÉN LA ACCIÓN NUEVA
insert into public.rate_limit_hits (action, origin_hash, day, hits) values ('report', repeat('7', 64), (now() at time zone 'utc')::date - 10, 3);
do $$
begin
  if public.purge_expired_rate_limit_hits() < 1 then raise exception 'the purge left an old report counter'; end if;
  if exists (select 1 from public.rate_limit_hits where origin_hash = repeat('7', 64)) then raise exception 'old report counter still there'; end if;
  if not exists (select 1 from public.rate_limit_hits where action = 'report' and origin_hash = repeat('1', 64)) then raise exception 'the purge removed today''s counter'; end if;
end $$;

rollback;
