-- Read-only checks for 20261119140000. Run each query on its own. / Consultas de solo lectura; correr cada una por separado.

-- 1. Expected: 35 therapies, 26 active, 9 hidden (33 before, +2 new; the 3 reactivated by 20261119130000 are already counted).
--    Esperado: 35 terapias, 26 activas, 9 ocultas.
select count(*) as total, count(*) filter (where is_active) as activas, count(*) filter (where not is_active) as ocultas
from public.therapies;

-- 2. Expected: 2 rows, both active, each with its Spanish name. / Esperado: 2 filas, activas, con su nombre en español.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id
where t.code in ('vibrational_therapy', 'social_process_facilitation')
order by t.sort_order;
