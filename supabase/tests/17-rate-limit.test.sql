-- Rate limit by origin for the contact reveal (ADR-0003): limit, isolation, error code, validation, purge, roles.
-- Límite de pedidos por origen para el revelado de contacto (ADR-0003): límite, aislamiento, código de error, validación,
-- purga y roles. Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000005' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000005' || k)::uuid, ('00000000-0000-0000-0000-0000000005' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2','ad']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000005ad'::uuid, id from public.roles where code = 'admin';
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000005' || k)::uuid, ('10000000-0000-0000-0000-0000000005' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '10 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1), 'Perfil ' || k
  from unnest(array['a1','a2']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select ('20000000-0000-0000-0000-0000000005' || x.k)::uuid, ct.id, x.v, false
  from (values ('a1','phone','+54 351 555 0501'), ('a1','email','canary-a1-rl@example.test'), ('a2','phone','+54 351 555 0502')) x(k, t, v)
  join public.contact_types ct on ct.code = x.t;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000005a1', '20000000-0000-0000-0000-0000000005a2');
-- a2 goes to paused: it must still COUNT against the limit when asked for / a2 pasa a pausado: igual CUENTA contra el límite
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused'), status_reason = 'test'
  where id = '20000000-0000-0000-0000-0000000005a2';

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare r text; f text; p text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.rate_limit_hits'::regclass) then raise exception 'rate_limit_hits has no RLS'; end if;
  if (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
       where table_schema = 'public' and table_name = 'rate_limit_hits') <> array['id', 'action', 'origin_hash', 'day', 'hits'] then
    raise exception 'rate_limit_hits columns changed: nothing but action, origin_hash, day and hits may be stored';
  end if;
  if exists (select 1 from pg_policy where polrelid = 'public.rate_limit_hits'::regclass) then raise exception 'rate_limit_hits must have no policies'; end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['select', 'insert', 'update', 'delete'] loop
      if has_table_privilege(r, 'public.rate_limit_hits', p) then raise exception '% has % on rate_limit_hits', r, p; end if;
    end loop;
  end loop;
  foreach f in array array['public.reveal_contact_limited(uuid, text)', 'public.purge_expired_rate_limit_hits()'] loop
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% must be SECURITY DEFINER', f; end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=pg_catalog, public']) then
      raise exception '% needs a fixed search_path', f;
    end if;
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% must be executable by service_role only', f;
    end if;
  end loop;
end $$;

-- 2) SETTINGS (as owner) / AJUSTES
do $$
declare v text;
begin
  if (select value::text from public.app_settings where key = 'reveal_daily_limit') <> '20' then raise exception 'default limit must be 20'; end if;
  if (select value::text from public.app_settings where key = 'retention_rate_limit_days') <> '2' then raise exception 'default retention must be 2 days'; end if;
  if exists (select 1 from public.app_settings where key in ('reveal_daily_limit', 'retention_rate_limit_days') and is_public) then
    raise exception 'rate-limit settings must be private';
  end if;
  foreach v in array array['0', '10001', '-1', '2.5', '"veinte"', 'true', 'null', '100000'] loop
    begin update public.app_settings set value = v::jsonb where key = 'reveal_daily_limit'; raise exception 'limit % accepted', v;
    exception when check_violation then null; end;
  end loop;
  foreach v in array array['0', '31', '-1', '1.5', '"dos"', 'false', '100'] loop
    begin update public.app_settings set value = v::jsonb where key = 'retention_rate_limit_days'; raise exception 'retention % accepted', v;
    exception when check_violation then null; end;
  end loop;
  update public.app_settings set value = '10000' where key = 'reveal_daily_limit';   -- upper edge ok / borde superior ok
  update public.app_settings set value = '1' where key = 'reveal_daily_limit';       -- lower edge ok / borde inferior ok
  update public.app_settings set value = '3' where key = 'reveal_daily_limit';
end $$;

-- 3) LIMIT, ISOLATION AND ERROR CODE (as service_role, the only door) / LÍMITE, AISLAMIENTO Y CÓDIGO DE ERROR
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
declare
  h1 text := repeat('1', 64); h2 text := repeat('2', 64); h3 text := repeat('3', 64); h4 text := repeat('4', 64);
  n int; i int; blocked boolean; msg text; bad text;
begin
  -- three allowed, each returns the 2 private contacts / tres permitidas, cada una devuelve los 2 contactos privados
  for i in 1..3 loop
    select count(*) into n from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', h1);
    if n <> 2 then raise exception 'call % of origin 1 returned % rows', i, n; end if;
  end loop;
  -- the fourth is blocked with SQLSTATE RL429 and reveals nothing / la cuarta se bloquea con RL429 y no revela nada
  blocked := false;
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', h1);
  exception when sqlstate 'RL429' then blocked := true; get stacked diagnostics msg = message_text; end;
  if not blocked then raise exception 'the 4th reveal of origin 1 was not blocked'; end if;
  if msg <> 'rate limit reached' then raise exception 'unexpected message: %', msg; end if;
  -- the limit belongs to the origin, not to the profile / el límite es del origen, no del perfil
  blocked := false;
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a2', h1);
  exception when sqlstate 'RL429' then blocked := true; end;
  if not blocked then raise exception 'origin 1 got through on another profile'; end if;
  begin perform * from public.reveal_contact_limited('99999999-9999-9999-9999-999999999999', h1); raise exception 'origin 1 got through on an unknown profile';
  exception when sqlstate 'RL429' then null; end;
  -- another origin is not affected / otro origen no se afecta
  select count(*) into n from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', h2);
  if n <> 2 then raise exception 'origin 2 was affected by origin 1 (% rows)', n; end if;
  -- guessing ids is not free: unknown and paused profiles count too / adivinar ids no sale gratis: inexistentes y pausados cuentan
  perform * from public.reveal_contact_limited('99999999-9999-9999-9999-999999999999', h3);
  perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a2', h3);
  perform * from public.reveal_contact_limited(null, h3);
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', h3); raise exception 'origin 3 got a contact after 3 empty guesses';
  exception when sqlstate 'RL429' then null; end;
  -- a null profile counts too / un perfil nulo también cuenta
  perform * from public.reveal_contact_limited(null, h4);
  -- invalid hashes: error 22023 and nothing is stored / hashes inválidos: error 22023 y no se guarda nada
  foreach bad in array array[repeat('A', 64), repeat('1', 63), repeat('1', 65), '203.0.113.7', '2001:db8::1', '', ' ' || repeat('1', 63), repeat('g', 64)] loop
    begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', bad); raise exception 'hash [%] accepted', bad;
    exception when sqlstate '22023' then null; end;
  end loop;
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', null); raise exception 'null hash accepted';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
reset session authorization;

-- 3b) WHAT WAS STORED (as owner) / LO QUE SE GUARDÓ
do $$
declare c1 int; hits1 int; hits2 int; hits3 int; hits4 int; n int;
begin
  select hits into hits1 from public.rate_limit_hits where origin_hash = repeat('1', 64);
  select hits into hits2 from public.rate_limit_hits where origin_hash = repeat('2', 64);
  select hits into hits3 from public.rate_limit_hits where origin_hash = repeat('3', 64);
  select hits into hits4 from public.rate_limit_hits where origin_hash = repeat('4', 64);
  select count(*) into n from public.rate_limit_hits;
  if hits1 <> 3 or hits2 <> 1 or hits3 <> 3 or hits4 <> 1 or n <> 4 then
    raise exception 'stored hits: o1 %, o2 %, o3 %, o4 %, rows % (expected 3,1,3,1,4: blocked calls and invalid hashes store nothing)', hits1, hits2, hits3, hits4, n;
  end if;
  if exists (select 1 from public.rate_limit_hits where action <> 'reveal' or day <> (now() at time zone 'utc')::date) then raise exception 'action must be reveal and day today (UTC)'; end if;
  -- the per-profile counter only grew for allowed reveals of a published profile: 3 (o1) + 1 (o2) / el contador por perfil solo creció en las permitidas
  select reveals_count into c1 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000005a1';
  if c1 <> 4 then raise exception 'contact_reveals for a1 should be 4, is %', c1; end if;
  -- a raw address can never be stored / una dirección real nunca se puede guardar
  begin insert into public.rate_limit_hits (action, origin_hash, day) values ('reveal', '203.0.113.7', current_date); raise exception 'raw address stored';
  exception when check_violation then null; end;
  begin insert into public.rate_limit_hits (action, origin_hash, day) values ('Reveal', repeat('5', 64), current_date); raise exception 'bad action stored';
  exception when check_violation then null; end;
  begin insert into public.rate_limit_hits (action, origin_hash, day, hits) values ('reveal', repeat('5', 64), current_date, 0); raise exception 'zero hits stored';
  exception when check_violation then null; end;
  begin insert into public.rate_limit_hits (action, origin_hash, day) values ('reveal', repeat('1', 64), (now() at time zone 'utc')::date); raise exception 'duplicate counter row';
  exception when unique_violation then null; end;
end $$;

-- 3c) LIMIT IS A SETTING, DAY AND ACTION WINDOWS / EL LÍMITE ES UN AJUSTE, VENTANAS DE DÍA Y ACCIÓN
update public.app_settings set value = '4' where key = 'reveal_daily_limit';
insert into public.rate_limit_hits (action, origin_hash, day, hits) values
  ('reveal', repeat('6', 64), (now() at time zone 'utc')::date - 1, 3),     -- yesterday: does not count today / ayer: hoy no cuenta
  ('other',  repeat('7', 64), (now() at time zone 'utc')::date, 3);          -- another action: does not count here / otra acción: acá no cuenta
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
declare n int;
begin
  -- origin 1 had 3 with limit 3; raising to 4 gives exactly one more / el origen 1 tenía 3; con 4 hay exactamente uno más
  perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('1', 64));
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('1', 64)); raise exception 'limit 4 let a 5th through';
  exception when sqlstate 'RL429' then null; end;
  -- yesterday's and another action's counters do not use today's reveal slots / los contadores de ayer y de otra acción no gastan lugares
  for n in 1..4 loop perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('6', 64)); end loop;
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('6', 64)); raise exception 'origin 6 passed 4';
  exception when sqlstate 'RL429' then null; end;
  for n in 1..4 loop perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('7', 64)); end loop;
end $$;
reset role;
reset session authorization;
update public.app_settings set value = '2' where key = 'reveal_daily_limit';
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
begin
  -- lowering below the current count blocks at once (origin 1 has 4) / bajar el límite por debajo de lo contado bloquea de inmediato
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('1', 64)); raise exception 'lowered limit ignored';
  exception when sqlstate 'RL429' then null; end;
  -- origin 2 had 1: one more passes, the next does not / el origen 2 tenía 1: pasa uno más, el siguiente no
  perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('2', 64));
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('2', 64)); raise exception 'origin 2 passed 2';
  exception when sqlstate 'RL429' then null; end;
end $$;
reset role;
reset session authorization;
-- missing setting: closed, not open / ajuste ausente: cerrado, no abierto
do $$
declare saved jsonb;
begin
  select value into saved from public.app_settings where key = 'reveal_daily_limit';
  delete from public.app_settings where key = 'reveal_daily_limit';
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('8', 64)); raise exception 'revealed without the limit setting';
  exception when check_violation then null; end;
  insert into public.app_settings (key, value, is_public, description) values ('reveal_daily_limit', saved, false, 'restored');
end $$;

-- 4) EVERY OTHER ROLE: no door, no table, no purge / TODOS LOS DEMÁS ROLES: sin puerta, sin tabla, sin purga
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('9', 64)); raise exception 'anon ran reveal_contact_limited';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'anon read rate_limit_hits';
  exception when insufficient_privilege then null; end;
  begin insert into public.rate_limit_hits (action, origin_hash, day) values ('reveal', repeat('9', 64), current_date); raise exception 'anon wrote rate_limit_hits';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_rate_limit_hits(); raise exception 'anon ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}', true);
do $$
begin
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('9', 64)); raise exception 'therapist ran reveal_contact_limited';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'therapist read rate_limit_hits';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_rate_limit_hits(); raise exception 'therapist ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005ad","role":"authenticated"}', true);
do $$
begin
  begin perform * from public.reveal_contact_limited('20000000-0000-0000-0000-0000000005a1', repeat('9', 64)); raise exception 'admin ran reveal_contact_limited';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'admin read rate_limit_hits';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_rate_limit_hits(); raise exception 'admin ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
-- the server role itself reads no table and cannot skip the limit through reveal_contact / ni el servidor lee la tabla ni se saltea el límite
set role service_role;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform 1 from public.rate_limit_hits; raise exception 'service_role read rate_limit_hits directly';
  exception when insufficient_privilege then null; end;
  begin perform * from public.reveal_contact('20000000-0000-0000-0000-0000000005a1'); raise exception 'service_role ran reveal_contact directly (skips the limit)';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 5) PURGE (service_role) / PURGA
delete from public.rate_limit_hits;
insert into public.rate_limit_hits (action, origin_hash, day) values
  ('reveal', repeat('a', 64), (now() at time zone 'utc')::date - 5),
  ('reveal', repeat('b', 64), (now() at time zone 'utc')::date - 3),
  ('reveal', repeat('c', 64), (now() at time zone 'utc')::date - 2),
  ('reveal', repeat('d', 64), (now() at time zone 'utc')::date - 1),
  ('reveal', repeat('e', 64), (now() at time zone 'utc')::date);
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_rate_limit_hits();
  if removed <> 2 then raise exception 'purge with 2 days should remove 2 rows (days -5 and -3), removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.rate_limit_hits) <> 3 or not exists (select 1 from public.rate_limit_hits where origin_hash = repeat('c', 64)) then
    raise exception 'purge removed the wrong rows (day -2 must stay with 2 days of retention)';
  end if;
  update public.app_settings set value = '1' where key = 'retention_rate_limit_days';
end $$;
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_rate_limit_hits();
  if removed <> 1 then raise exception 'purge with 1 day should remove 1 more row, removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.rate_limit_hits) <> 2 then raise exception 'purge left the wrong rows'; end if;
  delete from public.app_settings where key = 'retention_rate_limit_days';
end $$;
set session authorization authenticator;
set role service_role;
do $$
begin
  begin perform public.purge_expired_rate_limit_hits(); raise exception 'purge ran without its setting';
  exception when check_violation then null; end;
end $$;
reset role;
reset session authorization;

rollback;
select 'OK 17-rate-limit' as result;
