-- Catalog update, owner decisions of 20/11/2026. Reference data only: NOT a security change (no new table, grant, policy or
-- function). Idempotent: running it twice changes nothing the second time.
-- Actualización del catálogo, decisiones del titular del 20/11/2026. Solo datos de referencia: NO es un cambio de seguridad (sin
-- tablas, permisos, políticas ni funciones nuevas). Idempotente: correrla dos veces no cambia nada la segunda vez.
--
--  * "Yoga y Tai Chi / Qi Gong" was three disciplines in one entry. Only one profile uses it and it is a yoga practitioner, so the
--    existing row (same id, so profiles and revisions keep pointing at it) becomes "Yoga" and "Tai Chi" and "Qi Gong" are new.
--    "Yoga y Tai Chi / Qi Gong" eran tres disciplinas en una. Solo la usa un perfil y es de yoga, así que la fila existente (mismo
--    id: los perfiles y revisiones siguen apuntando a ella) pasa a ser "Yoga", y "Tai Chi" y "Qi Gong" son nuevas.
--  * Ayurveda and Quiropraxia (formerly "Quiropráctica") become active. They take free sort_order values (205, 206), because 210
--    and 250 were already used by other therapies.
--    Ayurveda y Quiropraxia (antes "Quiropráctica") pasan a estar activas. Usan valores de orden libres (205, 206), porque 210 y
--    250 ya los usaban otras terapias.
--  * Short names (cards): the name is replaced by a shorter one when it is longer than about 17 characters.
--    Nombres cortos (tarjetas): se reemplaza el nombre por uno más corto cuando pasa de unos 17 caracteres.

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
begin
  -- 1) The old combined therapy becomes "Yoga" / la terapia combinada vieja pasa a ser "Yoga"
  update public.therapies
  set code = 'yoga'
  where code = 'yoga_taichi_qigong'
    and not exists (select 1 from public.therapies where code = 'yoga');

  update public.therapy_translations tt
  set name = 'Yoga'
  from public.therapies t
  where t.id = tt.therapy_id and t.code = 'yoga' and tt.language_id = es and tt.name <> 'Yoga';

  -- 2) New therapies, right after Yoga (70) / terapias nuevas, justo después de Yoga (70)
  with catalog (code, name, sort_order) as (values
    ('tai_chi', 'Tai Chi', 71),
    ('qigong',  'Qi Gong', 72)
  ), inserted as (
    insert into public.therapies (code, sort_order, is_active)
    select c.code, c.sort_order, true from catalog c
    where not exists (select 1 from public.therapies t where t.code = c.code)
    returning id, code
  )
  insert into public.therapy_translations (therapy_id, language_id, name)
  select i.id, es, c.name from inserted i join catalog c using (code);

  -- 3) Reactivated / reactivadas
  update public.therapies set is_active = true, sort_order = 205 where code = 'ayurveda';
  update public.therapies set is_active = true, sort_order = 206 where code = 'chiropractic';

  update public.therapy_translations tt
  set name = 'Quiropraxia'
  from public.therapies t
  where t.id = tt.therapy_id and t.code = 'chiropractic' and tt.language_id = es and tt.name <> 'Quiropraxia';

  -- 4) Short names / nombres cortos. The first five were loaded by hand in the real database; they are listed here (no-op there) so
  --    that a database built from the migrations is identical to the real one.
  --    Los primeros cinco se cargaron a mano en la base real; se listan acá (sin efecto allá) para que una base armada desde las
  --    migraciones sea idéntica a la real.
  update public.therapy_translations tt
  set short_name = v.short_name
  from (values
    ('therapeutic_massage',         'Masajes'),
    ('hebrew_pendulum',             'Péndulo hebreo'),
    ('regression_therapy',          'Regresión'),
    ('acupuncture_tcm',             'Acupuntura'),
    ('social_process_facilitation', 'Procesos sociales'),
    ('meditation_mindfulness',      'Mindfulness'),
    ('heat_elements_massage',       'Masaje con calor'),
    ('cupping_moxibustion',         'Ventosas y moxa')
  ) as v(code, short_name), public.therapies t
  where t.code = v.code and tt.therapy_id = t.id and tt.language_id = es
    and tt.short_name is distinct from v.short_name;
end
$$;
