-- Catalog update, owner decisions of 17/11/2026: four new massage-related therapies. Reference data only: NOT a security change
-- (no new table, grant, policy or function).
-- Actualización del catálogo, decisiones del titular del 17/11/2026: cuatro terapias nuevas del rubro masajes. Solo datos de
-- referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas ni funciones nuevas).
--
--  * "Masajes Terapéuticos" and "Reflexología" already exist; the specific techniques (relajante, descontracturante,
--    californiano, deportivo, Tok Sen, reflexología tailandesa...) go in the per-therapy short description, not in the catalog.
--    "Masajes Terapéuticos" y "Reflexología" ya existen; las técnicas puntuales van en la descripción corta de cada terapia.
--  * Names avoid health conditions on purpose (moderation rule: no promises of cure or treatment of illnesses).
--    Los nombres no nombran condiciones de salud a propósito (regla de moderación: sin promesas de cura ni tratamientos).

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  with catalog (code, name, sort_order) as (values
    ('thai_massage',        'Masaje tailandés',             180),
    ('heat_elements_massage','Masaje con calor y elementos', 190),
    ('cupping_moxibustion', 'Ventosas y moxibustión',       200),
    ('shiatsu',             'Shiatsu',                      210)
  ), inserted as (
    insert into public.therapies (code, sort_order, is_active)
    select code, sort_order, true from catalog
    returning id, code
  )
  insert into public.therapy_translations (therapy_id, language_id, name)
  select i.id, es, c.name from inserted i join catalog c using (code);
end
$$;
