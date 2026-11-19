-- Verification for 20261119120000_add_city_ciudad_de_buenos_aires.sql
-- Verificacion de 20261119120000_add_city_ciudad_de_buenos_aires.sql
--
-- Expected / Esperado: exactly 1 row, level_id = 3, name = 'Ciudad de Buenos Aires',
-- region = 'Ciudad Autónoma de Buenos Aires'.
select
  c.id,
  c.level_id,
  rt.name as region,
  ct.name as city
from locations c
join location_translations ct on ct.location_id = c.id and ct.language_id = 1
join locations r on r.id = c.parent_id
join location_translations rt on rt.location_id = r.id and rt.language_id = 1
where c.level_id = 3
  and ct.name = 'Ciudad de Buenos Aires';
