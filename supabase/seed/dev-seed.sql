-- DEVELOPMENT sample data (therapies and locations). NEVER applied to production.
-- Datos de ejemplo para DESARROLLO (terapias y ubicaciones). NUNCA se aplican en producción.
--
-- The therapy list is a placeholder: the real initial list is pending the owner's decision.
-- La lista de terapias es provisoria: la lista inicial real está pendiente de decisión del titular.
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
  t record;
  c record;
  country_id integer;
  region_id integer;
  city_id integer;
  n integer := 0;
begin
  -- Therapies (placeholder list) / Terapias (lista provisoria)
  for t in select * from (values
      ('reiki', 'Reiki'),
      ('quantum_therapy', 'Terapia cuántica'),
      ('family_constellations', 'Constelaciones familiares'),
      ('akashic_records', 'Registros akáshicos'),
      ('biodecoding', 'Biodescodificación')
    ) as v(code, name)
  loop
    n := n + 1;
    insert into public.therapies (code, sort_order) values (t.code, n) on conflict (code) do nothing;
    insert into public.therapy_translations (therapy_id, language_id, name)
      select id, es, t.name from public.therapies where code = t.code
      on conflict do nothing;
  end loop;

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
