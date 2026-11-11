-- DEVELOPMENT sample data (locations). NEVER applied to production.
-- Datos de ejemplo para DESARROLLO (ubicaciones). NUNCA se aplican en producción.
--
-- Therapies are NOT here any more: the initial catalog is a migration (20261111110000).
-- Las terapias ya no están acá: el catálogo inicial es una migración (20261111110000).
-- Locations use real, public geography; there are no people, contacts or personal data here.
-- Las ubicaciones usan geografía pública real; no hay personas, contactos ni datos personales.
-- Safe to run twice / Se puede correr dos veces.

begin;

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
  lvl_country smallint := (select id from public.location_levels where code = 'country');
  lvl_region  smallint := (select id from public.location_levels where code = 'region');
  lvl_city    smallint := (select id from public.location_levels where code = 'city');
  c record;
  country_id integer;
  region_id integer;
  city_id integer;
begin
  -- Locations: country (iso, currency), region, city / Ubicaciones: país, región, ciudad
  for c in select * from (values
      ('AR', 'ARS', 'Argentina', 'Córdoba', 'Córdoba'),
      ('AR', 'ARS', 'Argentina', 'Santa Fe', 'Rosario'),
      ('CL', 'CLP', 'Chile', 'Región Metropolitana', 'Santiago'),
      ('MX', 'MXN', 'México', 'Jalisco', 'Guadalajara'),
      ('ES', 'EUR', 'España', 'Cataluña', 'Barcelona')
    ) as v(iso, cur, country, region, city)
  loop
    select l.id into country_id from public.locations l where l.iso_code = c.iso;
    if country_id is null then
      insert into public.locations (level_id, iso_code, default_currency_id)
        values (lvl_country, c.iso, (select id from public.currencies where code = c.cur))
        returning id into country_id;
      insert into public.location_translations values (country_id, es, c.country);
    end if;

    select l.id into region_id
      from public.locations l join public.location_translations lt on lt.location_id = l.id and lt.language_id = es
      where l.parent_id = country_id and l.level_id = lvl_region and lt.name = c.region;
    if region_id is null then
      insert into public.locations (level_id, parent_id) values (lvl_region, country_id) returning id into region_id;
      insert into public.location_translations values (region_id, es, c.region);
    end if;

    select l.id into city_id
      from public.locations l join public.location_translations lt on lt.location_id = l.id and lt.language_id = es
      where l.parent_id = region_id and l.level_id = lvl_city and lt.name = c.city;
    if city_id is null then
      insert into public.locations (level_id, parent_id) values (lvl_city, region_id) returning id into city_id;
      insert into public.location_translations values (city_id, es, c.city);
    end if;
  end loop;
end
$$;

commit;
