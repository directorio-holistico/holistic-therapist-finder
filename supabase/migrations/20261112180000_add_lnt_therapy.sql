-- Adds the LNT therapy to the catalog (reference data; not a security change: no new tables, grants or policies).
-- Agrega la terapia LNT al catálogo (dato de referencia; no es un cambio de seguridad: sin tablas, permisos ni políticas nuevas).
--
-- Public name of the method as the owner gave it. The bare internal code "LNT" of another system stays out of the
-- catalog (test 06 still checks it). Active from the start: it is the therapy the project was born around.
-- Nombre público del método tal como lo dio el titular. El código interno "LNT" a secas de otro sistema sigue fuera del
-- catálogo (la prueba 06 lo sigue verificando). Activa desde el inicio: es la terapia alrededor de la cual nació el proyecto.
--
-- sort_order 5 places it before the first seeded therapy (10) wherever the order is by sort_order.
-- sort_order 5 la ubica antes de la primera terapia cargada (10) donde el orden sea por sort_order.

with new_therapy as (
  insert into public.therapies (code, sort_order, is_active)
  values ('lnt_schwiderski', 5, true)
  returning id
)
insert into public.therapy_translations (therapy_id, language_id, name)
select id, (select id from public.languages where code = 'es'), 'LNT® - La Nueva Terapia - Método Schwiderski'
from new_therapy;
