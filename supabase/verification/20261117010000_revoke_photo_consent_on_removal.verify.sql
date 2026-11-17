-- Read-only checks for the REAL project after applying 20261117010000 / Solo lectura, proyecto REAL.
-- Removing a photo withdraws the photo consent. SECURITY CHANGE: 1 trigger function (security definer), 1 trigger.
-- Quitar una foto retira el consentimiento de la foto. CAMBIO DE SEGURIDAD: 1 función de trigger (security definer), 1 trigger.

-- 1) The trigger exists once, on therapist_profiles, AFTER UPDATE OF photo_path. Expected / Esperado: 1 row
select t.tgname, c.relname as table_name, pg_get_triggerdef(t.oid) as definition
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where t.tgname = 'therapist_profiles_photo_removed' and not t.tgisinternal;

-- 2) The function is security definer with a fixed search_path. Expected / Esperado: true | {search_path=pg_catalog, public}
select p.prosecdef as security_definer, p.proconfig from pg_proc p where p.oid = 'public.revoke_photo_consent_on_removal()'::regprocedure;

-- 3) No API role can execute it. Expected / Esperado: anon = false | authenticated = false | service_role = false
select has_function_privilege('anon', 'public.revoke_photo_consent_on_removal()', 'execute') as anon,
       has_function_privilege('authenticated', 'public.revoke_photo_consent_on_removal()', 'execute') as authenticated,
       has_function_privilege('service_role', 'public.revoke_photo_consent_on_removal()', 'execute') as service_role;

-- 4) The consent evidence is still there (nothing deleted). Expected / Esperado: counts only, no error
select count(*) filter (where revoked_at is null) as active, count(*) filter (where revoked_at is not null) as withdrawn
  from public.terms_acceptances ta
  join public.legal_document_types d on d.id = ta.document_type_id and d.code = 'photo_consent';
