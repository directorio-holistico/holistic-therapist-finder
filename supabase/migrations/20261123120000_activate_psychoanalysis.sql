-- Activate "Psicoanálisis y psicoterapia psicoanalítica" (decision of the site owner, 23/11/2026).
-- Activar "Psicoanálisis y psicoterapia psicoanalítica" (decisión del dueño del sitio, 23/11/2026).
-- It was loaded hidden because it is a regulated health profession and licences cannot be verified yet.
-- Se cargó oculta porque es una profesión de salud regulada y todavía no se pueden verificar matrículas.
-- Without this, approving a revision that picks it fails with 22023 "unknown or inactive therapy".
-- Sin esto, aprobar una revisión que la elige falla con 22023 "unknown or inactive therapy".
-- Idempotent / Idempotente: running it twice changes nothing.

begin;

update public.therapies
   set is_active = true
 where code = 'psychoanalysis'
   and is_active = false;

-- Verification / Verificación: expected 1 row, is_active = true
select id, code, is_active from public.therapies where code = 'psychoanalysis';

commit;
