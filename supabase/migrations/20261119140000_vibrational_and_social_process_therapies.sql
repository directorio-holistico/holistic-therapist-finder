-- Catalog update, owner decision of 19/11/2026: two new therapies asked for by a therapist. Reference data only: NOT a security
-- change (no new table, grant, policy or function). Idempotent: a therapy whose code already exists is not inserted again.
-- Actualización del catálogo, decisión del titular del 19/11/2026: dos terapias nuevas pedidas por un terapeuta. Solo datos de
-- referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas ni funciones nuevas). Idempotente: una terapia cuyo
-- código ya existe no se vuelve a insertar.
--
--  * Names are short and describe the TYPE of therapy; the detail goes in the per-therapy short description (as with the massages).
--    Los nombres son cortos y describen el TIPO de terapia; el detalle va en la descripción corta de cada terapia.
--  * No short_name: both names are under 40 characters, so the card shows the full name.
--    Sin short_name: ambos nombres tienen menos de 40 caracteres, la tarjeta muestra el nombre completo.

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  with catalog (code, name, sort_order) as (values
    ('vibrational_therapy',         'Terapia vibracional',              220),
    ('social_process_facilitation', 'Facilitador de procesos sociales', 230)
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
