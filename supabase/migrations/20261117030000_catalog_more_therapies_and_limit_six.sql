-- Catalog update, owner decisions of 17/11/2026: 5 new therapies, "Constelaciones familiares" renamed to "Constelaciones",
-- and the limit of therapies per profile raised from 4 to 6. Reference data and one setting: NOT a security change
-- (no new table, grant, policy or function).
-- Actualización del catálogo, decisiones del titular del 17/11/2026: 5 terapias nuevas, "Constelaciones familiares" pasa a
-- llamarse "Constelaciones" y el límite de terapias por perfil sube de 4 a 6. Datos de referencia y un ajuste: NO es un cambio
-- de seguridad (sin tablas, permisos, políticas ni funciones nuevas).
--
--  * Active from the start: Access Bars, cacao ceremony, hebrew pendulum, regression therapy (energy and mind-body practices).
--    Activas desde el inicio: Barras de Access, ceremonia de cacao, péndulo hebreo, terapia de regresión.
--  * Loaded but HIDDEN: psychoanalysis. It is a regulated health profession and the system cannot verify a licence yet
--    (verification is a Phase 2 item). Activate it only when that exists:
--      update public.therapies set is_active = true where code = 'psychoanalysis';
--    Cargada pero OCULTA: psicoanálisis. Es una profesión de salud regulada y el sistema todavía no puede verificar una
--    matrícula (la verificación es de la Fase 2). Se activa recién cuando exista.
--  * The name "Terapia de regresión" has no health condition on purpose: the moderation rule forbids promising cures or
--    treating illnesses. / El nombre "Terapia de regresión" no nombra ninguna condición de salud a propósito: la regla de
--    moderación prohíbe prometer curas o tratar enfermedades.
--  * The website mirrors the limit in two constants (src/lib/profile-form.ts and src/lib/legal/facts.ts) and the terms of use
--    quote it (new version). / La web refleja el límite en dos constantes y los términos de uso lo citan (versión nueva).

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
  changed integer;
begin
  -- 1. New therapies / Terapias nuevas
  with catalog (code, name, sort_order, is_active) as (values
    ('access_bars',       'Barras de Access',                          140, true),
    ('cacao_ceremony',    'Ceremonia de cacao',                        150, true),
    ('hebrew_pendulum',   'Péndulo hebreo cabalístico',                160, true),
    ('regression_therapy','Terapia de regresión',                      170, true),
    ('psychoanalysis',    'Psicoanálisis y psicoterapia psicoanalítica', 300, false)
  ), inserted as (
    insert into public.therapies (code, sort_order, is_active)
    select code, sort_order, is_active from catalog
    returning id, code
  )
  insert into public.therapy_translations (therapy_id, language_id, name)
  select i.id, es, c.name from inserted i join catalog c using (code);

  -- 2. Rename / Cambio de nombre
  update public.therapy_translations tt
     set name = 'Constelaciones'
    from public.therapies t
   where t.id = tt.therapy_id and t.code = 'family_constellations' and tt.language_id = es;
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'expected to rename exactly 1 therapy (family_constellations), got %', changed;
  end if;

  -- 3. Limit of therapies per profile / Límite de terapias por perfil
  update public.app_settings set value = '6'::jsonb where key = 'max_therapies_per_profile';
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'expected to update exactly 1 setting (max_therapies_per_profile), got %', changed;
  end if;
end
$$;
