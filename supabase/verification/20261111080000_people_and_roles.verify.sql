-- Read-only checks for the REAL Supabase project, after applying 20261111080000 / Solo lectura, proyecto REAL.
-- 1) Expected: people and person_roles with rls_enabled = true / Esperado: rls_enabled = true en ambas.
select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and relname in ('people', 'person_roles');
-- 2) Expected: only SELECT for authenticated; NOTHING for anon or service_role.
-- Esperado: solo SELECT para authenticated; NADA para anon ni service_role.
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name in ('people', 'person_roles') order by 1, 2, 3;
-- 3) Expected: EXECUTE only for authenticated (and the owner) / Esperado: EXECUTE solo para authenticated (y el dueño).
select (aclexplode(proacl)).grantee::regrole as grantee, (aclexplode(proacl)).privilege_type
from pg_proc where oid = 'public.is_admin()'::regprocedure;
-- 4) Expected: 4 policies, all SELECT / Esperado: 4 políticas, todas SELECT.
select tablename, policyname, roles, cmd from pg_policies
where schemaname = 'public' and tablename in ('people', 'person_roles') order by 1, 2;
