-- Catalog update, owner decision of 20/11/2026: one new entry asked for by a therapist. Reference data only: NOT a security
-- change (no new table, grant, policy or function). Idempotent: a therapy whose code already exists is not inserted again.
-- Actualización del catálogo, decisión del titular del 20/11/2026: una entrada nueva pedida por un terapeuta. Solo datos de
-- referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas ni funciones nuevas). Idempotente: una terapia cuyo
-- código ya existe no se vuelve a insertar.
--
--  * Transitional: retreats and trips are an ACTIVITY, not a therapy. It is listed here so it can be found in the search until a
--    separate "activities" catalog exists (courses, classes, congresses); then this entry is deactivated.
--    Transitorio: retiros y viajes son una ACTIVIDAD, no una terapia. Se lista acá para poder encontrarla en el buscador hasta que
--    exista un catálogo aparte de "actividades" (cursos, clases, congresos); entonces esta entrada se desactiva.
--  * No short_name: the name is under 40 characters, so the card shows the full name.
--    Sin short_name: el nombre tiene menos de 40 caracteres, la tarjeta muestra el nombre completo.

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  with catalog (code, name, sort_order) as (values
    ('retreats_and_trips', 'Retiros y viajes', 260)
  ), inserted as (
    insert into public.therapies (code, sort_order, is_active)
    select c.code, c.sort_order, true from catalog c
    where not exists (select 1 from public.therapies t where t.code = c.code)
    returning id, code
  )
  insert into public.therapy_translations (therapy_id, language_id, name)
  select i.id, es, c.name from inserted i join catalog c using (code);
end
$$;
