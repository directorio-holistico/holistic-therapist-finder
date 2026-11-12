-- Initial locations: complete, consistent, and visible to visitors (anon).
-- Ubicaciones iniciales: completas, consistentes y visibles para los visitantes (anon).
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
  c record;
begin
  for c in select * from (values ('AR', 'ARS', 24), ('MX', 'MXN', 32), ('ES', 'EUR', 19)) as v(iso, cur, regions) loop
    if not exists (select 1 from public.locations l join public.currencies cu on cu.id = l.default_currency_id
                   where l.iso_code = c.iso and cu.code = c.cur and l.parent_id is null and l.is_active) then
      raise exception 'country % missing or with wrong currency', c.iso;
    end if;
    if (select count(*) from public.locations r join public.locations p on p.id = r.parent_id
        where p.iso_code = c.iso and r.level_id = (select id from public.location_levels where code = 'region')) <> c.regions then
      raise exception 'country % must have % regions', c.iso, c.regions;
    end if;
  end loop;

  -- Chile is NOT a launch country (the local dev seed may add it; the migration must not) / Chile no es de lanzamiento
  -- every location has a Spanish name / toda ubicación tiene nombre en español
  if exists (select 1 from public.locations l
             where not exists (select 1 from public.location_translations t where t.location_id = l.id and t.language_id = es)) then
    raise exception 'a location has no Spanish name';
  end if;
  -- no repeated region name under the same country / sin nombres de región repetidos bajo el mismo país
  if exists (select 1 from public.locations r join public.location_translations t on t.location_id = r.id and t.language_id = es
             where r.parent_id is not null
             group by r.parent_id, lower(t.name) having count(*) > 1) then
    raise exception 'duplicated location name under the same parent';
  end if;
  -- spot checks / controles puntuales
  if not exists (select 1 from public.location_translations where name = 'Ciudad Autónoma de Buenos Aires') then raise exception 'CABA missing'; end if;
  if not exists (select 1 from public.location_translations where name = 'Ciudad de México') then raise exception 'CDMX missing'; end if;
  if not exists (select 1 from public.location_translations where name in ('Ceuta')) or
     not exists (select 1 from public.location_translations where name in ('Melilla')) then raise exception 'Ceuta/Melilla missing'; end if;
end
$$;

-- Visitors (anon) read countries and regions / Los visitantes (anon) leen países y regiones.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.locations where level_id = (select id from public.location_levels where code = 'region')
        and parent_id in (select id from public.locations where iso_code in ('AR', 'MX', 'ES'))) < 75 then
    raise exception 'anon must see the 75 regions of AR, MX and ES';
  end if;
  if (select count(*) from public.location_translations where name in ('Neuquén', 'Río Negro', 'Jalisco', 'Cataluña')) < 4 then
    raise exception 'anon cannot read region names';
  end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: locations seed is complete and visible to visitors / ubicaciones iniciales completas y visibles para los visitantes'
