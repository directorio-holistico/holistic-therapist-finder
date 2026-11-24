-- Catalog update, decision of the site owner of 24/11/2026: one new therapy asked for by a therapist (to be reviewed again once
-- the therapist answers). Reference data only: NOT a security change (no new table, grant, policy or function).
-- Idempotent: a therapy whose code already exists is not inserted again.
-- Actualización del catálogo, decisión del dueño del sitio del 24/11/2026: una terapia nueva pedida por un terapeuta (se vuelve a
-- revisar cuando el terapeuta responda). Solo datos de referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas
-- ni funciones nuevas). Idempotente: una terapia cuyo código ya existe no se vuelve a insertar.
--
--  * Active for everyone from the start. / Activa para todos desde el inicio.
--  * No short_name: the name is under 40 characters, so the card shows the full name.
--    Sin short_name: el nombre tiene menos de 40 caracteres, la tarjeta muestra el nombre completo.

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  with catalog (code, name, sort_order) as (values
    ('transpersonal_coaching', 'Coaching transpersonal', 270)
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
