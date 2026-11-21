-- Verification for 20261120204500_yoga_split_and_catalog_updates.sql. Read-only.
-- Verificación de 20261120204500_yoga_split_and_catalog_updates.sql. Solo lectura.

-- 1) Expected: 3 rows: yoga 70 'Yoga', tai_chi 71 'Tai Chi', qigong 72 'Qi Gong', all active.
-- 1) Esperado: 3 filas: yoga 70 'Yoga', tai_chi 71 'Tai Chi', qigong 72 'Qi Gong', todas activas.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where t.code in ('yoga', 'tai_chi', 'qigong')
order by t.sort_order;

-- 2) Expected: 0 (the old combined code is gone) and 1 profile still using Yoga (same id as before).
-- 2) Esperado: 0 (el código combinado viejo ya no existe) y 1 perfil que sigue usando Yoga (mismo id de antes).
select (select count(*) from public.therapies where code = 'yoga_taichi_qigong') as old_code_left,
       (select count(*) from public.profile_therapies pt join public.therapies t on t.id = pt.therapy_id where t.code = 'yoga') as profiles_with_yoga;

-- 3) Expected: 2 rows: ayurveda 205 'Ayurveda' and chiropractic 206 'Quiropraxia', both active.
-- 3) Esperado: 2 filas: ayurveda 205 'Ayurveda' y chiropractic 206 'Quiropraxia', ambas activas.
select t.code, tt.name, t.is_active, t.sort_order
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where t.code in ('ayurveda', 'chiropractic')
order by t.sort_order;

-- 4) Expected: 9 rows, the only therapies with a short name: LNT®, Masajes, Péndulo hebreo, Regresión, Acupuntura, Procesos sociales,
--    Mindfulness, Masaje con calor, Ventosas y moxa.
-- 4) Esperado: 9 filas, las únicas terapias con nombre corto: LNT®, Masajes, Péndulo hebreo, Regresión, Acupuntura, Procesos sociales,
--    Mindfulness, Masaje con calor, Ventosas y moxa.
select t.code, tt.name, tt.short_name
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
join public.languages l on l.id = tt.language_id and l.code = 'es'
where tt.short_name is not null
order by t.code;

-- 5) Expected: total 40, active 33.
-- 5) Esperado: total 40, activas 33.
select count(*) as total, count(*) filter (where is_active) as active from public.therapies;

-- 6) Expected: 0 rows (no Spanish name is repeated).
-- 6) Esperado: 0 filas (ningún nombre en español repetido).
select lower(tt.name) as name, count(*) as times
from public.therapy_translations tt
join public.languages l on l.id = tt.language_id and l.code = 'es'
group by lower(tt.name)
having count(*) > 1;
