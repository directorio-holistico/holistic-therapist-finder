-- Verification: exactly one active city "Olivos" under the region "Buenos Aires". / Verificación: exactamente una ciudad activa "Olivos" bajo la región "Buenos Aires".
select count(*) as olivos_cities
from public.locations c
join public.location_levels cl on cl.id = c.level_id and cl.code = 'city'
join public.location_translations ct on ct.location_id = c.id and ct.language_id = (select id from public.languages where code = 'es')
join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = ct.language_id
where c.is_active and ct.name = 'Olivos' and rt.name = 'Buenos Aires';
