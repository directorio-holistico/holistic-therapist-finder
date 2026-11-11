-- Read-only checks for the REAL project after applying 20261111120000 / Solo lectura, proyecto REAL.
-- 1) Expected: 3 tables, rls_enabled = true / Esperado: 3 tablas con rls_enabled = true.
select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and relname in ('restricted_terms', 'profile_revisions', 'moderation_events') order by 1;
-- 2) Expected: anon has NOTHING; authenticated: SELECT on all, INSERT/UPDATE/DELETE only on restricted_terms.
-- Esperado: anon NADA; authenticated: SELECT en todas, INSERT/UPDATE/DELETE solo en restricted_terms.
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name in ('restricted_terms', 'profile_revisions', 'moderation_events') order by 2, 1, 3;
-- 3) Expected: column grants only for profile_revisions (insert: profile_id, payload, suggested_therapy; update: payload, suggested_therapy).
-- Esperado: permisos por columna solo en profile_revisions.
select grantee, table_name, column_name, privilege_type from information_schema.role_column_grants
where table_schema = 'public' and table_name = 'profile_revisions' and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE') order by 4, 3;
-- 4) Expected: EXECUTE only for authenticated on find_restricted_terms and normalize_text.
-- Esperado: EXECUTE solo para authenticated.
select p.proname, (aclexplode(p.proacl)).grantee::regrole as grantee from pg_proc p
where p.proname in ('find_restricted_terms', 'normalize_text') and p.pronamespace = 'public'::regnamespace order by 1, 2;
