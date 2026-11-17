-- Rate limit for sign-in actions and the unmet-search log: the only doors, counts, isolation, settings, roles.
-- Límite de pedidos para las acciones de ingreso y el registro de búsquedas sin resultado: las únicas puertas, conteos,
-- aislamiento, ajustes y roles. Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1.

begin;

select set_config('test.t2', (select id::text from public.therapies where is_active order by id limit 1 offset 1), true),
       set_config('test.city', (select l.id::text from public.locations l join public.location_levels ll on ll.id = l.level_id
                                 where ll.code = 'city' and l.is_active order by l.id limit 1), true);

-- 1) STRUCTURE AND SETTINGS (as owner) / ESTRUCTURA Y AJUSTES
do $$
declare f text; v text; k text;
begin
  foreach f in array array['public.rate_limit_hit(text, text)', 'public.log_search_limited(integer, integer, text, text)'] loop
    if not (select prosecdef from pg_proc where oid = f::regprocedure) then raise exception '% must be SECURITY DEFINER', f; end if;
    if not exists (select 1 from pg_proc where oid = f::regprocedure and proconfig @> array['search_path=pg_catalog, public']) then
      raise exception '% needs a fixed search_path', f; end if;
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      raise exception '% must be executable by service_role only', f; end if;
  end loop;
  f := 'public.log_search(integer, integer, text)';
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception 'the direct door log_search must be closed to every API role'; end if;

  for k, v in select * from (values ('login_daily_limit', '30'), ('login_link_daily_limit', '10'), ('unmet_search_daily_limit', '50')) x(k, v) loop
    if (select value::text from public.app_settings where key = k) <> v then raise exception 'default of % must be %', k, v; end if;
    if (select is_public from public.app_settings where key = k) then raise exception '% must be private', k; end if;
  end loop;
  foreach v in array array['0', '-1', '2.5', '"diez"', 'true', 'null', '100000', '1001'] loop
    begin update public.app_settings set value = v::jsonb where key = 'login_daily_limit'; raise exception 'login limit % accepted', v;
    exception when check_violation then null; end;
    begin update public.app_settings set value = v::jsonb where key = 'login_link_daily_limit'; raise exception 'link limit % accepted', v;
    exception when check_violation then null; end;
  end loop;
  foreach v in array array['0', '-1', '2.5', '"diez"', 'true', 'null', '1000000', '10001'] loop
    begin update public.app_settings set value = v::jsonb where key = 'unmet_search_daily_limit'; raise exception 'search limit % accepted', v;
    exception when check_violation then null; end;
  end loop;
  update public.app_settings set value = '1000' where key = 'login_daily_limit';
  update public.app_settings set value = '10000' where key = 'unmet_search_daily_limit';
  update public.app_settings set value = '30' where key = 'login_daily_limit';
  update public.app_settings set value = '50' where key = 'unmet_search_daily_limit';
  -- the settings that existed before still obey their rules / los ajustes anteriores siguen con sus reglas
  begin update public.app_settings set value = '0' where key = 'reveal_daily_limit'; raise exception 'reveal limit 0 accepted';
  exception when check_violation then null; end;
end $$;

-- 2) ROLES: visitors and users cannot call anything here / ROLES: visitantes y usuarios no pueden llamar nada acá
set session authorization authenticator;
set role anon;
do $$
begin
  begin perform public.rate_limit_hit('login', repeat('1', 64)); raise exception 'anon ran rate_limit_hit';
  exception when insufficient_privilege then null; end;
  begin perform public.log_search(current_setting('test.t2')::int, current_setting('test.city')::int); raise exception 'anon ran log_search';
  exception when insufficient_privilege then null; end;
  begin perform public.log_search_limited(current_setting('test.t2')::int, current_setting('test.city')::int, null, repeat('1', 64)); raise exception 'anon ran log_search_limited';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'anon read the counters';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}', true);
do $$
begin
  begin perform public.rate_limit_hit('login', repeat('1', 64)); raise exception 'authenticated ran rate_limit_hit';
  exception when insufficient_privilege then null; end;
  begin perform public.log_search_limited(current_setting('test.t2')::int, current_setting('test.city')::int, null, repeat('1', 64)); raise exception 'authenticated ran log_search_limited';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.rate_limit_hits; raise exception 'authenticated read the counters';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 3) THE LIMITS AS service_role: count, edges, isolation between origins and between actions
set session authorization authenticator;
set role service_role;
do $$
declare
  h1 text := repeat('1', 64); h2 text := repeat('2', 64); i int; bad text; ok boolean;
begin
  -- 30 password attempts pass, the 31st does not (and keeps not passing) / 30 pasan, la 31 no
  for i in 1..30 loop
    if not public.rate_limit_hit('login', h1) then raise exception 'login attempt % of origin 1 was blocked', i; end if;
  end loop;
  if public.rate_limit_hit('login', h1) then raise exception 'the 31st login attempt of origin 1 passed'; end if;
  if public.rate_limit_hit('login', h1) then raise exception 'origin 1 passed again after the limit'; end if;
  -- another origin and another action are not affected / otro origen y otra acción no se afectan
  if not public.rate_limit_hit('login', h2) then raise exception 'origin 2 was blocked by origin 1'; end if;
  if not public.rate_limit_hit('login_link', h1) then raise exception 'login_link of origin 1 was blocked by its login counter'; end if;
  -- links: 10 pass, the 11th does not / enlaces: 10 pasan, el 11 no
  for i in 2..10 loop
    if not public.rate_limit_hit('login_link', h1) then raise exception 'link % of origin 1 was blocked', i; end if;
  end loop;
  if public.rate_limit_hit('login_link', h1) then raise exception 'the 11th link of origin 1 passed'; end if;
  -- invalid input: 22023 and NOT counted / entrada inválida: 22023 y NO se cuenta
  foreach bad in array array[repeat('g', 64), repeat('A', 64), repeat('1', 63), repeat('1', 65), '', 'x'] loop
    begin perform public.rate_limit_hit('login', bad); raise exception 'accepted hash %', bad;
    exception when sqlstate '22023' then null; end;
  end loop;
  begin perform public.rate_limit_hit('login', null); raise exception 'accepted null hash'; exception when sqlstate '22023' then null; end;
  begin perform public.rate_limit_hit(null, h2); raise exception 'accepted null action'; exception when sqlstate '22023' then null; end;
  foreach bad in array array['reveal', 'report', 'inventada', 'LOGIN', ''] loop
    begin perform public.rate_limit_hit(bad, h2); raise exception 'accepted action %', bad;
    exception when sqlstate '22023' then null; end;
  end loop;
  -- origin 2 used only 1 of 30 so far: 29 more pass, then it stops (proves nothing invalid was counted)
  for i in 2..30 loop
    if not public.rate_limit_hit('login', h2) then raise exception 'origin 2 attempt % blocked (invalid calls were counted?)', i; end if;
  end loop;
  if public.rate_limit_hit('login', h2) then raise exception 'the 31st attempt of origin 2 passed'; end if;
end $$;

-- 4) THE UNMET-SEARCH LOG: limit, false (not an error), invalid searches not counted / EL REGISTRO DE BÚSQUEDAS SIN RESULTADO
reset role;
reset session authorization;
update public.app_settings set value = '2' where key = 'unmet_search_daily_limit';
set session authorization authenticator;
set role service_role;
do $$
declare
  t2 int := current_setting('test.t2')::int; city int := current_setting('test.city')::int; h text := repeat('3', 64);
begin
  -- an invalid search fails and is not counted / una búsqueda inválida falla y no se cuenta
  begin perform public.log_search_limited(-1, city, null, h); raise exception 'accepted unknown therapy'; exception when sqlstate '22023' then null; end;
  begin perform public.log_search_limited(t2, -1, null, h); raise exception 'accepted unknown location'; exception when sqlstate '22023' then null; end;
  begin perform public.log_search_limited(t2, city, 'inventado', h); raise exception 'accepted unknown mode'; exception when sqlstate '22023' then null; end;
  -- the limit is 2: two are recorded, the third returns false and records nothing / el límite es 2
  if not public.log_search_limited(t2, city, null, h) then raise exception 'first unmet search not recorded'; end if;
  if not public.log_search_limited(t2, city, null, h) then raise exception 'second unmet search not recorded'; end if;
  if public.log_search_limited(t2, city, null, h) then raise exception 'third unmet search recorded over the limit'; end if;
  -- another origin still records / otro origen todavía registra
  if not public.log_search_limited(t2, city, null, repeat('4', 64)) then raise exception 'origin 4 was blocked by origin 3'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  -- 2 (origin 3) + 1 (origin 4) = 3 searches counted, none from the over-limit call
  if (select coalesce(sum(searches_count), 0) from public.unmet_searches
       where therapy_id = current_setting('test.t2')::int and location_id = current_setting('test.city')::int) <> 3 then
    raise exception 'unmet_searches has the wrong total'; end if;
  -- the counters hold only hashes, never anything readable / los contadores guardan solo hashes
  if exists (select 1 from public.rate_limit_hits where origin_hash !~ '^[0-9a-f]{64}$') then raise exception 'a counter has no hash'; end if;
  if exists (select 1 from public.rate_limit_hits where action not in ('login', 'login_link', 'unmet_search')) then raise exception 'unexpected action in the counters'; end if;
  -- changing the setting changes the behavior at once / cambiar el ajuste cambia el comportamiento al instante
  update public.app_settings set value = '50' where key = 'unmet_search_daily_limit';
end $$;

rollback;
select 'OK 34-rate-limit-login-and-search-log' as result;
