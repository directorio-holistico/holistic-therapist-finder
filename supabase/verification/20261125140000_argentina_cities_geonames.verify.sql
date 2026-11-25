-- Read-only checks for 20261125140000_argentina_cities_geonames.sql. / Comprobaciones de solo lectura.
-- Expected / esperado: regiones = 24, regiones_sin_ciudad = 0, ciudades_repetidas = 0, olivos = 1, martinez = 1, beccar = 1,
-- ciudades_en_caba = 1. total_ciudades should be about 961 plus the few cities that were already loaded under another spelling
-- (if it is much higher, or ciudades_repetidas is not 0, send me the result: do not commit).
-- total_ciudades debería ser cerca de 961 más las pocas ciudades que ya estaban cargadas con otra grafía
-- (si es mucho mayor, o ciudades_repetidas no es 0, mandame el resultado: no hagas commit).
with es as (select id from public.languages where code = 'es'),
ar as (select id from public.locations where level_id = (select id from public.location_levels where code = 'country') and iso_code = 'AR'),
reg as (select l.id from public.locations l where l.level_id = (select id from public.location_levels where code = 'region') and l.parent_id = (select id from ar)),
city as (
  select l.id, l.parent_id, t.name,
         lower(translate(t.name, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) as norm
    from public.locations l
    join public.location_translations t on t.location_id = l.id and t.language_id = (select id from es)
   where l.level_id = (select id from public.location_levels where code = 'city') and l.parent_id in (select id from reg))
select jsonb_build_object(
  'regiones', (select count(*) from reg),
  'total_ciudades', (select count(*) from city),
  'regiones_sin_ciudad', (select count(*) from reg where id not in (select parent_id from city)),
  'ciudades_repetidas', (select count(*) from (select parent_id, norm from city group by parent_id, norm having count(*) > 1) d),
  'olivos', (select count(*) from city where norm = 'olivos'),
  'martinez', (select count(*) from city where norm = 'martinez'),
  'beccar', (select count(*) from city where norm = 'beccar'),
  'ciudades_en_caba', (select count(*) from city c join public.location_translations t on t.location_id = c.parent_id and t.language_id = (select id from es) where t.name = 'Ciudad Autónoma de Buenos Aires'),
  'por_region_top', (select jsonb_agg(x order by x.ciudades desc) from (
      select t.name as region, count(*) as ciudades from city c
        join public.location_translations t on t.location_id = c.parent_id and t.language_id = (select id from es)
       group by t.name order by count(*) desc limit 5) x)
) as verificacion;
