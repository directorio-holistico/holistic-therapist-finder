-- Read-only checks for the REAL project after applying 20261124160000 / Solo lectura, proyecto REAL.
-- Expected / Esperado:
--   functions: approve_revision(uuid, text) and delete_my_approval_note(uuid) -> anon_can = false, auth_can = true, security_definer = true;
--   exactly 1 approve_revision overload (the old one is gone); column_exists = 1; constraint_exists = 1.
--   funciones: anon_can = false, auth_can = true, security_definer = true; exactamente 1 versión de approve_revision; columna = 1; restricción = 1.
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       has_function_privilege('anon', p.oid, 'execute') as anon_can,
       has_function_privilege('authenticated', p.oid, 'execute') as auth_can,
       p.prosecdef as security_definer
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('approve_revision', 'delete_my_approval_note')
 order by p.proname;
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profile_revisions' and column_name = 'approval_note') as column_exists,
       (select count(*) from pg_constraint where conrelid = 'public.profile_revisions'::regclass and conname = 'profile_revisions_note_only_when_decided') as constraint_exists;
