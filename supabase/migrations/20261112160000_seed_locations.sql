-- Initial locations: countries and regions for the launch markets (reference data every environment needs).
-- NOT a security change: no new tables, grants or policies. Cities are loaded in a later migration.
-- Ubicaciones iniciales: países y regiones de los mercados de lanzamiento (datos de referencia que todo ambiente necesita).
-- NO es un cambio de seguridad: no hay tablas, permisos ni políticas nuevas. Las ciudades van en una migración posterior.
--
-- Launch countries (owner decision 12/11/2026): Argentina, México, España. Chile is left out for now.
-- Regions: Argentina = 24 jurisdictions (23 provinces + Ciudad Autónoma de Buenos Aires);
--          México = 32 states (31 + Ciudad de México);  España = 19 (17 autonomous communities + Ceuta + Melilla).
-- Países de lanzamiento (decisión del titular, 12/11/2026): Argentina, México, España. Chile queda afuera por ahora.
-- Regiones: Argentina = 24 jurisdicciones (23 provincias + Ciudad Autónoma de Buenos Aires);
--           México = 32 estados (31 + Ciudad de México);  España = 19 (17 comunidades autónomas + Ceuta + Melilla).
-- Names are Spanish (the UI starts in Spanish); other languages are added through location_translations.
-- Los nombres están en español (la interfaz arranca en español); otros idiomas se suman en location_translations.
-- Public geography only: no personal data. / Solo geografía pública: sin datos personales.

do $$
declare
  es          smallint := (select id from public.languages where code = 'es');
  lvl_country smallint := (select id from public.location_levels where code = 'country');
  lvl_region  smallint := (select id from public.location_levels where code = 'region');
  c           record;
  country_id  integer;
  region_id   integer;
  r           text;
  n           smallint;
begin
  for c in select * from (values
    ('AR', 'ARS', 'Argentina', array[
      'Buenos Aires', 'Catamarca', 'Chaco', 'Chubut', 'Ciudad Autónoma de Buenos Aires', 'Córdoba',
      'Corrientes', 'Entre Ríos', 'Formosa', 'Jujuy', 'La Pampa', 'La Rioja', 'Mendoza', 'Misiones',
      'Neuquén', 'Río Negro', 'Salta', 'San Juan', 'San Luis', 'Santa Cruz', 'Santa Fe',
      'Santiago del Estero', 'Tierra del Fuego', 'Tucumán']),
    ('MX', 'MXN', 'México', array[
      'Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche', 'Chiapas', 'Chihuahua',
      'Ciudad de México', 'Coahuila', 'Colima', 'Durango', 'Estado de México', 'Guanajuato', 'Guerrero',
      'Hidalgo', 'Jalisco', 'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca', 'Puebla',
      'Querétaro', 'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora', 'Tabasco', 'Tamaulipas',
      'Tlaxcala', 'Veracruz', 'Yucatán', 'Zacatecas']),
    ('ES', 'EUR', 'España', array[
      'Andalucía', 'Aragón', 'Asturias', 'Canarias', 'Cantabria', 'Castilla y León', 'Castilla-La Mancha',
      'Cataluña', 'Ceuta', 'Comunidad Valenciana', 'Extremadura', 'Galicia', 'Islas Baleares', 'La Rioja',
      'Comunidad de Madrid', 'Melilla', 'Navarra', 'País Vasco', 'Región de Murcia'])
  ) as v(iso, cur, country, regions)
  loop
    select l.id into country_id from public.locations l where l.iso_code = c.iso;
    if country_id is null then
      insert into public.locations (level_id, iso_code, default_currency_id)
        values (lvl_country, c.iso, (select id from public.currencies where code = c.cur))
        returning id into country_id;
      insert into public.location_translations (location_id, language_id, name) values (country_id, es, c.country);
    end if;

    n := 0;
    foreach r in array c.regions loop
      n := n + 1;
      select l.id into region_id
        from public.locations l
        join public.location_translations lt on lt.location_id = l.id and lt.language_id = es
        where l.parent_id = country_id and l.level_id = lvl_region and lt.name = r;
      if region_id is null then
        insert into public.locations (level_id, parent_id, sort_order) values (lvl_region, country_id, n)
          returning id into region_id;
        insert into public.location_translations (location_id, language_id, name) values (region_id, es, r);
      end if;
    end loop;
  end loop;
end
$$;
