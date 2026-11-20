-- Catalog update, owner decision of 19/11/2026: two new therapies asked for by therapists. Reference data only: NOT a security
-- change (no new table, grant, policy or function). Idempotent: a therapy whose code already exists is not inserted again.
-- Actualización del catálogo, decisión del titular del 19/11/2026: dos terapias nuevas pedidas por terapeutas. Solo datos de
-- referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas ni funciones nuevas). Idempotente: una terapia cuyo
-- código ya existe no se vuelve a insertar.
--
--  * Psychotherapy schools were also asked for and left out on purpose: the directory is holistic and does not list psychological
--    or medical practices. / También se pidieron escuelas de psicoterapia y se dejaron afuera a propósito: el directorio es holístico
--    y no lista prácticas psicológicas ni médicas.
--  * No short_name: both names are under 40 characters, so the card shows the full name.
--    Sin short_name: ambos nombres tienen menos de 40 caracteres, la tarjeta muestra el nombre completo.

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  with catalog (code, name, sort_order) as (values
    ('focusing',          'Focusing',              240),
    ('origin_reimprint',  'Reimpronta del origen', 250)
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
