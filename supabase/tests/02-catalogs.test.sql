-- Catalogs and locations: RLS on, anon/authenticated access, no writes, hierarchy guard.
-- Catálogos y ubicaciones: RLS activa, acceso de anon/authenticated, sin escrituras, guarda de jerarquía.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- 1) Every table in public has RLS enabled (guard for all future tables too).
-- 1) Toda tabla de public tiene RLS activada (guarda también para las tablas futuras).
do $$
declare
  r record;
begin
  for r in
    select c.relname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
  loop
    raise exception 'table public.% has RLS disabled', r.relname;
  end loop;
end
$$;

-- 2) anon may read ONLY the public catalogs, nothing else in public (checked against a written whitelist).
-- 2) anon puede leer SOLO los catálogos públicos y nada más en public (contra una lista blanca escrita).
do $$
declare
  allowed text[] := array[
    'languages', 'currencies', 'service_modes', 'session_formats', 'rate_audiences',
    'location_levels', 'therapies', 'therapy_translations', 'locations', 'location_translations'];
  r record;
begin
  for r in
    select table_name, privilege_type from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'
  loop
    if r.privilege_type <> 'SELECT' or not (r.table_name = any (allowed)) then
      raise exception 'anon has % on public.% (not in the whitelist)', r.privilege_type, r.table_name;
    end if;
  end loop;
  -- nobody but the owner writes catalogs / nadie salvo el dueño escribe catálogos
  -- the only table-level write grant is restricted_terms for authenticated (its policies limit it to admins)
  -- el único permiso de escritura de tabla es restricted_terms para authenticated (sus políticas lo limitan a admins)
  if exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
      and not (table_name = 'restricted_terms' and grantee = 'authenticated'
               and privilege_type in ('INSERT', 'UPDATE', 'DELETE'))) then
    raise exception 'an API role can write to a public table';
  end if;
end
$$;

-- Test data: one inactive therapy and one inactive country, created as the owner.
-- Datos de prueba: una terapia inactiva y un país inactivo, creados como dueño.
insert into public.therapies (code, is_active) values ('zz_active', true), ('zz_inactive', false);
insert into public.therapy_translations (therapy_id, language_id, name)
  select id, (select id from public.languages where code = 'es'), 'Activa __' from public.therapies where code = 'zz_active'
  union all
  select id, (select id from public.languages where code = 'es'), 'Inactiva __' from public.therapies where code = 'zz_inactive';

-- 3) anon: sees active rows only, and the reference data from the migration.
-- 3) anon: ve solo filas activas y los datos de referencia de la migración.
set session authorization authenticator;
set role anon;
do $$
begin
  if (select count(*) from public.therapies where code = 'zz_active') <> 1 then
    raise exception 'anon cannot read an active therapy';
  end if;
  if (select count(*) from public.therapies where code = 'zz_inactive') <> 0 then
    raise exception 'anon can read an INACTIVE therapy';
  end if;
  if (select count(*) from public.therapy_translations where name = 'Inactiva __') <> 0 then
    raise exception 'anon can read the translation of an INACTIVE therapy';
  end if;
  if (select count(*) from public.therapy_translations where name = 'Activa __') <> 1 then
    raise exception 'anon cannot read the translation of an active therapy';
  end if;
  if (select count(*) from public.currencies) <> 5 then
    raise exception 'anon should see the 5 currencies';
  end if;
end
$$;
reset role;
reset session authorization;

-- 4) anon cannot read internal catalogs (denied by privileges) nor write anywhere.
-- 4) anon no lee catálogos internos (se niega por permisos) ni escribe en ningún lado.
do $$
declare
  t text;
  denied boolean;
begin
  set local session authorization authenticator;
  set local role anon;
  foreach t in array array['contact_types', 'profile_statuses', 'revision_statuses', 'roles'] loop
    denied := false;
    begin
      execute format('select 1 from public.%I limit 1', t);
    exception when insufficient_privilege then denied := true;
    end;
    if not denied then
      raise exception 'anon could read internal catalog %', t;
    end if;
  end loop;

  foreach t in array array['therapies', 'languages', 'locations', 'currencies'] loop
    denied := false;
    begin
      execute format('delete from public.%I', t);
    exception when insufficient_privilege then denied := true;
    end;
    if not denied then
      raise exception 'anon could DELETE from %', t;
    end if;
  end loop;
  reset role;
  reset session authorization;
end
$$;

-- 5) authenticated: reads everything (inactive rows and internal catalogs) but cannot write.
-- 5) authenticated: lee todo (filas inactivas y catálogos internos) pero no escribe.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
do $$
declare
  denied boolean := false;
begin
  if (select count(*) from public.therapies where code = 'zz_inactive') <> 1 then
    raise exception 'authenticated cannot read an inactive therapy';
  end if;
  if (select count(*) from public.roles) <> 2 then
    raise exception 'authenticated should read the 2 roles';
  end if;
  if (select count(*) from public.contact_types where is_required) <> 1 then
    raise exception 'exactly one contact type must be required (phone)';
  end if;
  begin
    insert into public.therapies (code) values ('zz_hack');
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then
    raise exception 'authenticated could INSERT into therapies';
  end if;
end
$$;
reset role;
reset session authorization;

-- 6) Hierarchy guard (as owner): each invalid shape is rejected, each valid one accepted.
-- 6) Guarda de jerarquía (como dueño): cada forma inválida se rechaza, cada válida se acepta.
do $$
declare
  lc smallint := (select id from public.location_levels where code = 'country');
  lr smallint := (select id from public.location_levels where code = 'region');
  lt smallint := (select id from public.location_levels where code = 'city');
  cur smallint := (select id from public.currencies where code = 'USD');
  country_id integer;
  region_id integer;
  ok boolean;
begin
  insert into public.locations (level_id, iso_code, default_currency_id) values (lc, 'ZZ', cur) returning id into country_id;
  insert into public.locations (level_id, parent_id) values (lr, country_id) returning id into region_id;
  insert into public.locations (level_id, parent_id) values (lt, region_id);

  -- country without iso_code / país sin iso_code
  ok := false;
  begin insert into public.locations (level_id) values (lc);
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a country without iso_code was accepted'; end if;

  -- country with a parent / país con padre
  ok := false;
  begin insert into public.locations (level_id, parent_id, iso_code) values (lc, country_id, 'ZY');
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a country with a parent was accepted'; end if;

  -- region without a parent / región sin padre
  ok := false;
  begin insert into public.locations (level_id) values (lr);
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a region without a parent was accepted'; end if;

  -- city directly under a country (skips a level) / ciudad directo bajo un país (salta un nivel)
  ok := false;
  begin insert into public.locations (level_id, parent_id) values (lt, country_id);
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a city under a country was accepted'; end if;

  -- region with an iso_code / región con iso_code
  ok := false;
  begin insert into public.locations (level_id, parent_id, iso_code) values (lr, country_id, 'ZX');
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a region with iso_code was accepted'; end if;

  ok := false;
  begin update public.locations set parent_id = (select id from public.locations where level_id = lt limit 1)
        where id = region_id;
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a region under a city was accepted'; end if;
end
$$;

-- 7) Reference data from the migration is complete / Los datos de referencia de la migración están completos.
do $$
begin
  if (select count(*) from public.profile_statuses) <> 5 then raise exception 'profile_statuses must have 5 rows'; end if;
  if (select count(*) from public.revision_statuses) <> 5 then raise exception 'revision_statuses must have 5 rows'; end if;
  if (select count(*) from public.location_levels) <> 3 then raise exception 'location_levels must have 3 rows'; end if;
  if (select count(*) from public.service_modes) <> 2 then raise exception 'service_modes must have 2 rows'; end if;
  if (select count(*) from public.session_formats) <> 2 then raise exception 'session_formats must have 2 rows'; end if;
  if (select count(*) from public.rate_audiences) <> 2 then raise exception 'rate_audiences must have 2 rows'; end if;
  if (select count(*) from public.contact_types) <> 3 then raise exception 'contact_types must have 3 rows'; end if;
end
$$;

rollback;
\echo 'OK: catalogs and locations behave as designed / catalogos y ubicaciones segun el diseno'
