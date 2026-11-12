-- Starter cities (REAL public geography): 4 per launch country. NOT a security change (data only, no new table).
-- Ciudades iniciales (geografía pública REAL): 4 por país de lanzamiento. NO es cambio de seguridad (solo datos).
--
--  * A profile's base location must be a CITY (therapist_profiles_guard), and the real database had none.
--    La ubicación base de un perfil debe ser una CIUDAD (therapist_profiles_guard) y la base real no tenía ninguna.
--  * This is only a starter set; the owner loads the rest by hand later (source for Argentina still undecided).
--    Es solo un conjunto inicial; el dueño carga el resto a mano después (fuente para Argentina sin decidir).
--  * Idempotent: a city that already exists under its region is skipped (the local dev seed loads some of the same ones).
--    Idempotente: una ciudad que ya existe bajo su región se omite (el seed local carga algunas de las mismas).
--  * Fails loudly if a region name is not found, instead of silently loading nothing.
--    Falla en voz alta si no encuentra una región, en vez de no cargar nada en silencio.

do $$
declare
  es       smallint := (select id from public.languages where code = 'es');
  lvl_reg  smallint := (select id from public.location_levels where code = 'region');
  lvl_city smallint := (select id from public.location_levels where code = 'city');
  c        record;
  region_id integer;
  city_id   integer;
begin
  for c in select * from (values
    ('AR', 'Río Negro',                'Cinco Saltos'),
    ('AR', 'Córdoba',                  'Córdoba'),
    ('AR', 'Santa Fe',                 'Rosario'),
    ('AR', 'Mendoza',                  'Mendoza'),
    ('MX', 'Ciudad de México',         'Ciudad de México'),
    ('MX', 'Jalisco',                  'Guadalajara'),
    ('MX', 'Nuevo León',               'Monterrey'),
    ('MX', 'Yucatán',                  'Mérida'),
    ('ES', 'Comunidad de Madrid',      'Madrid'),
    ('ES', 'Cataluña',                 'Barcelona'),
    ('ES', 'Comunidad Valenciana',     'Valencia'),
    ('ES', 'Andalucía',                'Sevilla')
  ) as v(iso, region, city)
  loop
    select r.id into region_id
      from public.locations r
      join public.locations p on p.id = r.parent_id and p.iso_code = c.iso
      join public.location_translations t on t.location_id = r.id and t.language_id = es
      where r.level_id = lvl_reg and t.name = c.region;
    if region_id is null then
      raise exception 'region not found: % / %', c.iso, c.region;
    end if;

    select l.id into city_id
      from public.locations l
      join public.location_translations t on t.location_id = l.id and t.language_id = es
      where l.parent_id = region_id and l.level_id = lvl_city and t.name = c.city;
    if city_id is null then
      insert into public.locations (level_id, parent_id) values (lvl_city, region_id) returning id into city_id;
      insert into public.location_translations (location_id, language_id, name) values (city_id, es, c.city);
    end if;
  end loop;
end
$$;
