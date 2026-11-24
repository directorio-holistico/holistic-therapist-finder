-- Verification: exactly one active city "Colonia Avellaneda" under the region "Entre Ríos". / Verificación: exactamente una ciudad activa "Colonia Avellaneda" bajo la región "Entre Ríos".
select count(*) as colonia_avellaneda_cities
from public.locations c
join public.location_levels cl on cl.id = c.level_id and cl.code = 'city'
join public.location_translations ct on ct.location_id = c.id and ct.language_id = (select id from public.languages where code = 'es')
join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = ct.language_id
where c.is_active and ct.name = 'Colonia Avellaneda' and rt.name = 'Entre Ríos';
