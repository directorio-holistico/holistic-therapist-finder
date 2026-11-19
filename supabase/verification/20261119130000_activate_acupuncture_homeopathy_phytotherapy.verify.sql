-- Verification / Verificación. Run each query separately / Correr cada consulta por separado.

-- 1) Expected: 3 rows, all is_active = true / Esperado: 3 filas, todas activas.
select t.code, tt.name, t.is_active
  from public.therapies t
  join public.therapy_translations tt on tt.therapy_id = t.id
  join public.languages l on l.id = tt.language_id and l.code = 'es'
 where t.code in ('acupuncture_tcm', 'homeopathy', 'phytotherapy')
 order by t.code;

-- 2) Expected: 0 / Esperado: 0.
select count(*) as inactive_left
  from public.therapies
 where code in ('acupuncture_tcm', 'homeopathy', 'phytotherapy')
   and is_active = false;
