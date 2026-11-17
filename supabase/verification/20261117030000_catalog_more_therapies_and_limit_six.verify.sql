-- Read-only checks for 20261117030000. Run each query on its own. / Consultas de solo lectura; correr cada una por separado.

-- 1. Expected: 29 therapies, 17 active, 12 hidden. / Esperado: 29 terapias, 17 activas, 12 ocultas.
select count(*) as total, count(*) filter (where is_active) as activas, count(*) filter (where not is_active) as ocultas
from public.therapies;

-- 2. Expected: 5 rows; the first four active, psychoanalysis hidden. / Esperado: 5 filas; las cuatro primeras activas, psicoanálisis oculta.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id
where t.code in ('access_bars', 'cacao_ceremony', 'hebrew_pendulum', 'regression_therapy', 'psychoanalysis')
order by t.sort_order;

-- 3. Expected: "Constelaciones". / Esperado: "Constelaciones".
select t.code, tt.name from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id where t.code = 'family_constellations';

-- 4. Expected: 6. / Esperado: 6.
select value from public.app_settings where key = 'max_therapies_per_profile';
