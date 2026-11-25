-- Verification: the region is called "CABA", the old name is gone, and it still has its one city.
-- Verificación: la región se llama "CABA", el nombre viejo ya no está, y sigue teniendo su única ciudad.
-- Expected / esperado: regiones_caba = 1, regiones_nombre_viejo = 0, ciudades_en_caba = 1
select
  (select count(*) from public.location_translations t where t.name = 'CABA'
     and t.location_id in (select id from public.locations where level_id = (select id from public.location_levels where code = 'region'))) as regiones_caba,
  (select count(*) from public.location_translations where name = 'Ciudad Autónoma de Buenos Aires') as regiones_nombre_viejo,
  (select count(*) from public.locations c
     join public.location_translations rt on rt.location_id = c.parent_id
    where c.level_id = (select id from public.location_levels where code = 'city') and rt.name = 'CABA') as ciudades_en_caba;
