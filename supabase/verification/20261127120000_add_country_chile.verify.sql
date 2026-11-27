-- Verification of 20261127120000_add_country_chile / Verificación de 20261127120000_add_country_chile
-- Expected / Esperado: countries = 1, currency = CLP, regions = 16, cities = 36, duplicate_names = 0, without_spanish_name = 0.
select
  (select count(*) from public.locations where iso_code = 'CL' and is_active) as countries,
  (select c.code from public.locations l join public.currencies c on c.id = l.default_currency_id where l.iso_code = 'CL') as currency,
  (select count(*) from public.locations r join public.locations p on p.id = r.parent_id
     where p.iso_code = 'CL' and r.level_id = (select id from public.location_levels where code = 'region') and r.is_active) as regions,
  (select count(*) from public.locations c join public.locations r on r.id = c.parent_id join public.locations p on p.id = r.parent_id
     where p.iso_code = 'CL' and c.level_id = (select id from public.location_levels where code = 'city') and c.is_active) as cities,
  (select count(*) from (
     select r.id, t.name from public.locations r join public.locations p on p.id = r.parent_id
       join public.location_translations t on t.location_id = r.id
      where p.iso_code = 'CL' group by r.id, t.name having count(*) > 1) d) as duplicate_names,
  (select count(*) from public.locations l
     where (l.iso_code = 'CL' or l.parent_id in (select id from public.locations where iso_code = 'CL')
            or l.parent_id in (select r.id from public.locations r join public.locations p on p.id = r.parent_id where p.iso_code = 'CL'))
       and not exists (select 1 from public.location_translations t where t.location_id = l.id
                       and t.language_id = (select id from public.languages where code = 'es'))) as without_spanish_name;

-- The list, to look at it / La lista, para mirarla.
select rt.name as region, string_agg(ct.name, ', ' order by ct.name) as cities
from public.locations c
join public.locations r on r.id = c.parent_id
join public.locations p on p.id = r.parent_id and p.iso_code = 'CL'
join public.location_translations rt on rt.location_id = r.id
join public.location_translations ct on ct.location_id = c.id
where c.level_id = (select id from public.location_levels where code = 'city')
group by rt.name order by rt.name;
