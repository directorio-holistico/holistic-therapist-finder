-- Verification for 20261124120000_coaching_transpersonal_therapy.sql. Read-only.
-- Verificación de 20261124120000_coaching_transpersonal_therapy.sql. Solo lectura.

-- 1) Expected: 1 row (Coaching transpersonal), active.
-- 1) Esperado: 1 fila (Coaching transpersonal), activa.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where t.code = 'transpersonal_coaching';

-- 2) Expected: 0 (no other therapy already carries this name).
-- 2) Esperado: 0 (ninguna otra terapia ya tiene este nombre).
select count(*) as same_name_other_code
from public.therapy_translations tt
join public.therapies t on t.id = tt.therapy_id
where lower(tt.name) = 'coaching transpersonal'
  and t.code <> 'transpersonal_coaching';
