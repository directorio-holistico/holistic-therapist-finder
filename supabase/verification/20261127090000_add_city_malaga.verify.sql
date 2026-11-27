-- Verification: exactly one active city "Málaga" under the region "Andalucía". / Verificación: exactamente una ciudad activa "Málaga" bajo la región "Andalucía".
select count(*) as malaga_cities
from public.locations c
join public.location_levels cl on cl.id = c.level_id and cl.code = 'city'
join public.location_translations ct on ct.location_id = c.id and ct.language_id = (select id from public.languages where code = 'es')
join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = ct.language_id
join public.locations r on r.id = c.parent_id
join public.location_translations pt on pt.location_id = r.parent_id and pt.language_id = ct.language_id
where c.is_active and ct.name = 'Málaga' and rt.name = 'Andalucía' and pt.name = 'España';
