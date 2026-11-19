-- Activate three therapies that the therapist form already offered but the database kept hidden.
-- Activar tres terapias que el formulario ya ofrecía pero la base mantenía ocultas.
-- Without this, approving a revision that picks them fails with 22023 "unknown or inactive therapy".
-- Sin esto, aprobar una revisión que las elige falla con 22023 "unknown or inactive therapy".
-- Idempotent / Idempotente: running it twice changes nothing.

begin;

update public.therapies
   set is_active = true
 where code in ('acupuncture_tcm', 'homeopathy', 'phytotherapy')
   and is_active = false;

commit;
