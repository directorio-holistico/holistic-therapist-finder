-- Catalog update, decision of the site owner of 25/11/2026: add the therapy "Astrología". Reference data only: NOT a security change
-- (no new table, grant, policy or function). Idempotent: a therapy whose code already exists is not inserted again.
-- Actualización del catálogo, decisión del dueño del sitio del 25/11/2026: se agrega la terapia "Astrología". Solo datos de
-- referencia: NO es un cambio de seguridad (sin tablas, permisos, políticas ni funciones nuevas). Idempotente: una terapia cuyo
-- código ya existe no se vuelve a insertar.
--
--  * Active for everyone from the start. / Activa para todos desde el inicio.
--  * Spanish name in therapy_translations (names are translatable by design; only Spanish exists today).
--    Nombre en español en therapy_translations (los nombres son traducibles por diseño; hoy solo existe el español).
--  * No short_name: the name is under 40 characters. / Sin short_name: el nombre tiene menos de 40 caracteres.
--  * sort_order: at the end of the catalog (current maximum + 10), so it never collides. / Al final del catálogo (máximo actual + 10).
--  * If another therapy already has the same Spanish name (unique, case-insensitive), the insert stops with an error instead of
--    duplicating it. / Si otra terapia ya tiene el mismo nombre en español (único, sin importar mayúsculas), el alta se detiene con error.

do $$
declare
  es       smallint := (select id from public.languages where code = 'es');
  new_id   integer;
begin
  if es is null then
    raise exception 'language es not found';
  end if;

  if not exists (select 1 from public.therapies where code = 'astrology') then
    insert into public.therapies (code, sort_order, is_active)
    values ('astrology', (select (coalesce(max(sort_order), 0) + 10)::smallint from public.therapies), true)
    returning id into new_id;

    insert into public.therapy_translations (therapy_id, language_id, name)
    values (new_id, es, 'Astrología');
  end if;
end
$$;
