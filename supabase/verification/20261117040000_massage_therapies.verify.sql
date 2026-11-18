-- Read-only checks for 20261117040000. Run each query on its own. / Consultas de solo lectura; correr cada una por separado.

-- 1. Expected: 33 therapies, 21 active, 12 hidden. / Esperado: 33 terapias, 21 activas, 12 ocultas.
select count(*) as total, count(*) filter (where is_active) as activas, count(*) filter (where not is_active) as ocultas
from public.therapies;

-- 2. Expected: 4 rows, all active. / Esperado: 4 filas, todas activas.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id
where t.code in ('thai_massage', 'heat_elements_massage', 'cupping_moxibustion', 'shiatsu')
order by t.sort_order;
