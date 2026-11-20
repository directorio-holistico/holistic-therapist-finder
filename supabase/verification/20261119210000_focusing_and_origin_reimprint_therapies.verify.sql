-- Verification for 20261119210000_focusing_and_origin_reimprint_therapies.sql. Read-only.
-- Verificación de 20261119210000_focusing_and_origin_reimprint_therapies.sql. Solo lectura.

-- 1) Expected: 2 rows (Focusing, Reimpronta del origen), both active.
-- 1) Esperado: 2 filas (Focusing, Reimpronta del origen), ambas activas.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where t.code in ('focusing', 'origin_reimprint')
order by t.sort_order;

-- 2) Expected: 0 (no other therapy already carries one of these names).
-- 2) Esperado: 0 (ninguna otra terapia ya tiene uno de estos nombres).
select count(*) as same_name_other_code
from public.therapy_translations tt
join public.therapies t on t.id = tt.therapy_id
where lower(tt.name) in ('focusing', 'reimpronta del origen')
  and t.code not in ('focusing', 'origin_reimprint');
