-- Read-only checks for the REAL project after applying 20261112160000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: AR 24 regions (ARS), MX 32 (MXN), ES 19 (EUR); no other country; no cities yet.
select l.iso_code, cur.code as currency, lt.name as country,
       (select count(*) from public.locations r where r.parent_id = l.id) as regions
from public.locations l
join public.location_translations lt on lt.location_id = l.id
join public.currencies cur on cur.id = l.default_currency_id
where l.parent_id is null
order by l.iso_code;
select lv.code as level, count(*) from public.locations l join public.location_levels lv on lv.id = l.level_id group by 1 order by 1;
