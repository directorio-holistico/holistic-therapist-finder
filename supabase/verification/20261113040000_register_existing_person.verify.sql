-- Read-only checks for the REAL project after applying 20261113040000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: 1 row, security_definer = t, anon_can_execute = f, authenticated_can_execute = t.
select p.proname, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'register_therapist';
-- Expected / Esperado: the body mentions "on conflict do nothing" (new behaviour) / el cuerpo menciona la nueva lógica.
select position('on conflict' in pg_get_functiondef('public.register_therapist(text, jsonb)'::regprocedure)) > 0 as has_new_logic;
