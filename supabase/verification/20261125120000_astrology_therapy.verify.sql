-- Verification for 20261125120000_astrology_therapy.sql. Read-only. / Verificación de 20261125120000_astrology_therapy.sql. Solo lectura.

-- 1) Expected: 1 row (astrology, "Astrología", active, sort_order = last of the catalog).
-- 1) Esperado: 1 fila (astrology, "Astrología", activa, sort_order = el último del catálogo).
select t.id, t.code, tt.name, tt.short_name, t.is_active, t.sort_order,
       t.sort_order = (select max(sort_order) from public.therapies) as is_last
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where t.code = 'astrology';

-- 2) Expected: 0 (no other therapy carries this name, and no repeated names in the whole catalog).
-- 2) Esperado: 0 (ninguna otra terapia tiene este nombre, y no hay nombres repetidos en todo el catálogo).
select (select count(*) from public.therapy_translations tt join public.therapies t on t.id = tt.therapy_id
         where lower(tt.name) = 'astrología' and t.code <> 'astrology')
     + (select count(*) from (select 1 from public.therapy_translations group by language_id, lower(name) having count(*) > 1) d)
       as problems;
