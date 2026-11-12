-- Read-only checks for the REAL project after applying 20261112200000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: 12 cities (4 AR, 4 MX, 4 ES), each under its region.
select p.iso_code as country, rt.name as region, ct.name as city
from public.locations c
join public.location_levels ll on ll.id = c.level_id and ll.code = 'city'
join public.location_translations ct on ct.location_id = c.id
join public.locations r on r.id = c.parent_id
join public.location_translations rt on rt.location_id = r.id
join public.locations p on p.id = r.parent_id
order by p.iso_code, rt.name;
select count(*) as cities from public.locations where level_id = (select id from public.location_levels where code = 'city');
