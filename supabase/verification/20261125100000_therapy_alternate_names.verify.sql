-- Verification: the 8 therapies have the new name and short name (expected: 8 rows, ok = true in all). / Verificación: las 8 terapias tienen el nombre nuevo y el corto (esperado: 8 filas, ok = true en todas).
select t.code, tt.name, tt.short_name, t.is_active,
       (tt.name like '% / %' and char_length(tt.short_name) < char_length(tt.name)) as ok
  from public.therapies t
  join public.therapy_translations tt on tt.therapy_id = t.id
  join public.languages l on l.id = tt.language_id and l.code = 'es'
 where t.code in ('biofeedback','biodecoding','access_bars','qigong','tai_chi','chiropractic','thai_massage','cupping_moxibustion')
 order by t.code;
-- Must be 0: no therapy name repeated (case-insensitive) and no name over 120 characters. / Debe dar 0: sin nombres repetidos ni de más de 120 caracteres.
select (select count(*) from (select lower(name) from public.therapy_translations group by language_id, lower(name) having count(*) > 1) d)
     + (select count(*) from public.therapy_translations where char_length(name) > 120) as problems;
