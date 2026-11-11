-- Read-only checks for the REAL Supabase project, after applying 20261111100000 / Solo lectura, proyecto REAL.
-- 1) Expected: 3 tables with rls_enabled = true / Esperado: 3 tablas con rls_enabled = true.
select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and relname in ('app_settings', 'profile_therapy_rates', 'profile_contacts') order by 1;
-- 2) Expected: only SELECT for authenticated; NOTHING for anon / Esperado: solo SELECT para authenticated; NADA para anon.
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name in ('app_settings', 'profile_therapy_rates', 'profile_contacts') order by 1, 2, 3;
-- 3) Expected: ONE column-level grant: authenticated UPDATE on app_settings.value / Esperado: UN permiso por columna.
select grantee, table_name, column_name, privilege_type from information_schema.role_column_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role') and privilege_type in ('INSERT', 'UPDATE');
-- 4) Expected: 8 policies; the only non-SELECT one is app_settings_update_admin / Esperado: 8 políticas; la única no SELECT es app_settings_update_admin.
select tablename, policyname, roles, cmd from pg_policies
where schemaname = 'public' and tablename in ('app_settings', 'profile_therapy_rates', 'profile_contacts') order by 1, 2;
-- 5) Expected: 4 guard triggers enabled ('O') / Esperado: 4 triggers de guarda habilitados.
select tgrelid::regclass as table_name, tgname, tgenabled from pg_trigger
where not tgisinternal and tgname in ('profile_therapy_rates_guard', 'profile_therapies_limit', 'profile_contacts_guard', 'therapist_profiles_guard') order by 1, 2;
