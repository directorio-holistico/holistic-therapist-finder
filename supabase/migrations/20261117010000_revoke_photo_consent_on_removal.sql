-- Profile photos, part 3: when a photo is removed from a profile, the consent to show it is withdrawn.
-- SECURITY CHANGE: 1 trigger function (SECURITY DEFINER) and 1 trigger. No new table, column, policy or callable function.
-- Fotos de perfil, parte 3: cuando se quita la foto de un perfil, se retira el consentimiento para mostrarla.
-- CAMBIO DE SEGURIDAD: 1 función de trigger (SECURITY DEFINER) y 1 trigger. Sin tabla, columna, política ni función invocable nuevas.
--
-- Why / Por qué:
--   * The approval of a "remove my photo" request runs as the ADMINISTRATOR, so set_photo_consent (which acts on the logged-in
--     person) cannot withdraw the THERAPIST's consent from there. A trigger on the profile does it for every path
--     (approved revision, direct update by the server), without rewriting approve_revision / apply_revision_payload.
--     La aprobación de un pedido de "quitar mi foto" corre como ADMINISTRADOR, así que set_photo_consent (que actúa sobre la
--     persona con sesión) no puede retirar desde ahí el consentimiento de la TERAPEUTA. Un trigger sobre el perfil lo hace por
--     todos los caminos (revisión aprobada, actualización directa del servidor), sin reescribir approve_revision ni
--     apply_revision_payload.
--
-- Rules / Reglas:
--   * Fires only when photo_path goes from a value to NULL (a removal). Changing the photo for another one, or setting the first
--     photo, does not touch the consent.
--     Se dispara solo cuando photo_path pasa de un valor a NULL (una quita). Cambiar la foto por otra, o poner la primera, no
--     toca el consentimiento.
--   * It sets revoked_at = now() on every ACTIVE photo_consent row of the profile's person. Nothing is deleted: the history of
--     what was accepted and when is kept as evidence. The guard trigger of terms_acceptances still applies (only revoked_at
--     may change, and only on optional documents; photo_consent is optional).
--     Pone revoked_at = now() en cada fila ACTIVA de photo_consent de la persona del perfil. No se borra nada: la historia de lo
--     aceptado y cuándo queda como evidencia. El trigger de guarda de terms_acceptances sigue rigiendo.
--   * SECURITY DEFINER with a fixed search_path (terms_acceptances has no write grant for API roles). EXECUTE revoked from every
--     API role: a trigger function cannot be called directly anyway.
--     SECURITY DEFINER con search_path fijo (terms_acceptances no tiene permiso de escritura para los roles de la API). EXECUTE
--     revocado a todos los roles de la API: una función de trigger no se puede llamar directamente igual.
--   * Idempotent: CREATE OR REPLACE + DROP TRIGGER IF EXISTS. / Idempotente.

create or replace function public.revoke_photo_consent_on_removal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.terms_acceptances
     set revoked_at = now()
   where person_id = new.person_id
     and revoked_at is null
     and document_type_id = (select id from public.legal_document_types where code = 'photo_consent');
  return null;  -- AFTER trigger: the return value is ignored / trigger AFTER: se ignora el valor devuelto
end
$$;
revoke execute on function public.revoke_photo_consent_on_removal() from public, anon, authenticated, service_role;

drop trigger if exists therapist_profiles_photo_removed on public.therapist_profiles;
create trigger therapist_profiles_photo_removed
  after update of photo_path on public.therapist_profiles
  for each row
  when (old.photo_path is not null and new.photo_path is null)
  execute function public.revoke_photo_consent_on_removal();
