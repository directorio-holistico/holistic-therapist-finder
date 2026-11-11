-- Read-only checks for the REAL project after applying 20261111110000 / Solo lectura, proyecto REAL.
-- Expected: 13 active + 10 hidden, each with its Spanish name / Esperado: 13 activas + 10 ocultas, cada una con su nombre.
select t.is_active, count(*) as therapies, count(tt.name) as with_spanish_name
from public.therapies t left join public.therapy_translations tt on tt.therapy_id = t.id
group by t.is_active order by 1 desc;
