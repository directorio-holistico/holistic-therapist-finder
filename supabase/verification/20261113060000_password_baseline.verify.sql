-- Read-only checks for the REAL project after applying 20261113060000 / Solo lectura, proyecto REAL.
-- 1) Expected / Esperado: security_definer = t | volatility = v | anon_can_execute = f | authenticated_can_execute = t.
select p.proname, p.prosecdef as security_definer, p.provolatile as volatility,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'current_user_has_password';
-- 2) The new table is closed: RLS on, no privilege for any API role. Expected / Esperado: rls = t | 0 rows of grants.
select c.relrowsecurity as rls from pg_class c where c.oid = 'public.password_baselines'::regclass;
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'password_baselines' and grantee in ('anon', 'authenticated', 'service_role');
