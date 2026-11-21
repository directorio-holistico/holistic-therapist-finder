-- Read-only checks for 20261121190000_mexico_cities_geonames.sql. / Comprobaciones de solo lectura.
-- Expected / esperado: regiones_sin_ciudad = 0, ciudades_repetidas = 0, acayucan = 1, total_ciudades = 1726
-- (1726 if the 5 cities that were already loaded match by name; slightly more means one had another spelling: send me the list).
with es as (select id from public.languages where code = 'es'),
mx as (select id from public.locations where level_id = 1 and iso_code = 'MX'),
reg as (select l.id from public.locations l where l.level_id = 2 and l.parent_id = (select id from mx)),
city as (
  select l.id, l.parent_id, t.name,
         lower(translate(t.name, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) as norm
    from public.locations l
    join public.location_translations t on t.location_id = l.id and t.language_id = (select id from es)
   where l.level_id = 3 and l.parent_id in (select id from reg))
select jsonb_build_object(
  'regiones', (select count(*) from reg),
  'total_ciudades', (select count(*) from city),
  'regiones_sin_ciudad', (select count(*) from reg where id not in (select parent_id from city)),
  'ciudades_repetidas', (select count(*) from (select parent_id, norm from city group by parent_id, norm having count(*) > 1) d),
  'acayucan', (select count(*) from city where norm = 'acayucan'),
  'por_region_top', (select jsonb_agg(x order by x.ciudades desc) from (
      select t.name as region, count(*) as ciudades from city c
        join public.location_translations t on t.location_id = c.parent_id and t.language_id = (select id from es)
       group by t.name order by count(*) desc limit 5) x)
) as verificacion;
