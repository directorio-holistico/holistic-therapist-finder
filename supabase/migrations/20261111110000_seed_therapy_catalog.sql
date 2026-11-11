-- Initial therapy catalog (reference data every environment needs). Not a security change: no new tables or grants.
-- Catálogo inicial de terapias (datos de referencia que todo ambiente necesita). No es un cambio de seguridad.
--
-- Source: names proposed by the owner from a list of his own, plus three additions that match the
-- project focus (energy and quantum therapies). Descriptions are NOT stored: Phase 1 has no description
-- field, and several wording styles would collide with the "no cure claims" moderation rule.
-- Fuente: nombres que propuso el titular a partir de una lista propia, más tres agregados que responden al
-- foco del proyecto (terapias energéticas y cuánticas). NO se guardan descripciones: la Fase 1 no tiene campo
-- de descripción y varias redacciones chocarían con la regla de moderación "sin promesas de cura".
--
-- is_active = true  : energy and mind-body therapies, visible to visitors.
-- is_active = false : loaded but HIDDEN. Health practices that are regulated in many countries, or that sell
--                     products. Activating them is a business decision still open (update is_active later).
-- is_active = true  : terapias energéticas y mente-cuerpo, visibles para los visitantes.
-- is_active = false : cargadas pero OCULTAS. Prácticas de salud reguladas en muchos países, o que venden
--                     productos. Activarlas es una decisión de negocio todavía abierta.
-- Names are Spanish (the UI starts in Spanish); other languages are added through therapy_translations.
-- Los nombres están en español (la interfaz arranca en español); otros idiomas se suman en therapy_translations.

with catalog (code, name, sort_order, is_active) as (values
  ('reiki',                 'Reiki',                         10, true),
  ('therapeutic_touch',     'Toque Terapéutico',             20, true),
  ('dowsing',               'Radiestesia',                   30, true),
  ('biodecoding',           'BioDecodificación',             40, true),
  ('bioneuroemotion',       'BioNeuroEmoción',               50, true),
  ('meditation_mindfulness','Meditación y Mindfulness',      60, true),
  ('yoga_taichi_qigong',    'Yoga y Tai Chi / Qi Gong',      70, true),
  ('hypnotherapy',          'Hipnoterapia',                  80, true),
  ('reflexology',           'Reflexología',                  90, true),
  ('therapeutic_massage',   'Masajes Terapéuticos',         100, true),
  ('quantum_therapy',       'Terapia cuántica',             110, true),
  ('family_constellations', 'Constelaciones familiares',    120, true),
  ('akashic_records',       'Registros akáshicos',          130, true),
  ('acupuncture_tcm',       'Acupuntura (Medicina Tradicional China)', 200, false),
  ('ayurveda',              'Ayurveda',                     210, false),
  ('homeopathy',            'Homeopatía',                   220, false),
  ('naturopathy',           'Naturopatía',                  230, false),
  ('osteopathy',            'Osteopatía',                   240, false),
  ('chiropractic',          'Quiropráctica',                250, false),
  ('phytotherapy',          'Fitoterapia',                  260, false),
  ('dietotherapy',          'Dietoterapia',                 270, false),
  ('biofeedback',           'Biorretroalimentación',        280, false),
  ('dietary_supplements',   'Suplementos Dietéticos',       290, false)
), inserted as (
  insert into public.therapies (code, sort_order, is_active)
  select code, sort_order, is_active from catalog
  returning id, code
)
insert into public.therapy_translations (therapy_id, language_id, name)
select i.id, (select id from public.languages where code = 'es'), c.name
from inserted i join catalog c using (code);
