-- Add the city "Ciudad de Buenos Aires" under the region "Ciudad Autonoma de Buenos Aires".
-- Agrega la ciudad "Ciudad de Buenos Aires" bajo la region "Ciudad Autonoma de Buenos Aires".
--
-- Idempotent: it does nothing if the city already exists (it was first loaded by hand
-- in production on 2026-11-19, so this file only brings the repository in line).
-- Idempotente: no hace nada si la ciudad ya existe (se cargo a mano en produccion el
-- 2026-11-19; este archivo solo deja el repositorio alineado).
--
-- Catalog data only: no tables, policies or grants are touched.
-- Solo datos de catalogo: no se tocan tablas, politicas ni permisos.

with region as (
  select l.id
  from locations l
  join location_translations t on t.location_id = l.id and t.language_id = 1
  where l.level_id = 2
    and t.name = 'Ciudad Autónoma de Buenos Aires'
),
nueva as (
  insert into locations (level_id, parent_id, sort_order, is_active)
  select 3, r.id, 0, true
  from region r
  where not exists (
    select 1
    from locations c
    join location_translations ct on ct.location_id = c.id and ct.language_id = 1
    where c.parent_id = r.id
      and ct.name = 'Ciudad de Buenos Aires'
  )
  returning id
)
insert into location_translations (location_id, language_id, name)
select id, 1, 'Ciudad de Buenos Aires' from nueva;
