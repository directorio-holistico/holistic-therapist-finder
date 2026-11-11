-- Read-only checks for the REAL Supabase project, after applying 20261111070000 / Solo lectura, para el proyecto REAL.
-- 1) Expected: 14 rows, rls_enabled = true everywhere / Esperado: 14 filas, rls_enabled = true en todas.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by 1;
-- 2) Expected: anon only SELECT on the 10 public catalogs; no INSERT/UPDATE/DELETE for any API role.
-- Esperado: anon solo SELECT en los 10 catalogos publicos; ningun rol de la API con INSERT/UPDATE/DELETE.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
order by grantee, table_name, privilege_type;
-- 3) Expected: only *_select_anon and *_select_authenticated policies / Esperado: solo politicas de lectura.
select tablename, policyname, roles, cmd from pg_policies where schemaname = 'public' order by 1, 2;
