-- Short name for the psychoanalysis therapy (shown on cards). Catalog data only: no table, grant, policy or view change.
-- Nombre corto para la terapia de psicoanálisis (se muestra en las tarjetas). Solo dato de catálogo: sin cambios de tabla, permisos, políticas ni vistas.
-- The column therapy_translations.short_name already exists (20261116010000) and the public views already read it.
-- La columna therapy_translations.short_name ya existe (20261116010000) y las vistas públicas ya la leen.
-- Idempotent / Idempotente: running it twice changes nothing.

begin;

update public.therapy_translations tt
   set short_name = 'Psicoanálisis'
 where tt.therapy_id = (select t.id from public.therapies t where t.code = 'psychoanalysis')
   and tt.language_id = (select l.id from public.languages l where l.code = 'es')
   and tt.short_name is distinct from 'Psicoanálisis';

-- Verification / Verificación: expected 1 row, short_name = 'Psicoanálisis'
select t.code, tt.name, tt.short_name
  from public.therapy_translations tt
  join public.therapies t on t.id = tt.therapy_id
 where t.code = 'psychoanalysis';

commit;
