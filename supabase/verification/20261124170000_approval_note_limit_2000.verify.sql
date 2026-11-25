-- Read-only checks for the REAL project after applying 20261124170000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: one length check named profile_revisions_note_length with 2000 and no other check on char_length;
-- approve_revision(uuid, text): anon_can = false, auth_can = true, security_definer = true, source mentions 2000 and not 1000.
-- Esperado: una sola restricción de largo llamada profile_revisions_note_length con 2000; la función sin permiso para anon, con permiso
-- para authenticated, security definer, y su código menciona 2000 y no 1000.
select c.conname, pg_get_constraintdef(c.oid) as definition
  from pg_constraint c
 where c.conrelid = 'public.profile_revisions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%approval_note%'
 order by c.conname;
select p.oid::regprocedure as function_signature,
       has_function_privilege('anon', p.oid, 'execute') as anon_can,
       has_function_privilege('authenticated', p.oid, 'execute') as auth_can,
       p.prosecdef as security_definer,
       pg_get_functiondef(p.oid) like '%> 2000%' as limit_is_2000,
       pg_get_functiondef(p.oid) like '%> 1000%' as still_1000
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname = 'approve_revision';
