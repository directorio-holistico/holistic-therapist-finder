-- Read-only checks for the REAL project after applying 20261124140000 / Solo lectura, proyecto REAL.
-- Expected: 1 function; anon_can = false; auth_can = true (the admin check is inside); security_definer = true.
-- Esperado: 1 función; anon_can = false; auth_can = true (el chequeo de admin va dentro); security_definer = true.
select p.proname, has_function_privilege('anon', p.oid, 'execute') as anon_can, has_function_privilege('authenticated', p.oid, 'execute') as auth_can,
       p.prosecdef as security_definer
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'admin_dismiss_suggested_therapy';
