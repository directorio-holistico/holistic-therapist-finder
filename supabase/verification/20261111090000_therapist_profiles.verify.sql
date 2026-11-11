-- Read-only checks for the REAL Supabase project, after applying 20261111090000 / Solo lectura, proyecto REAL.
-- 1) Expected: 5 tables, rls_enabled = true / Esperado: 5 tablas con rls_enabled = true.
select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and relname in ('therapist_profiles','profile_therapies','profile_languages','profile_service_modes','profile_session_formats')
order by 1;
-- 2) Expected: only SELECT for authenticated; NOTHING for anon / Esperado: solo SELECT para authenticated; NADA para anon.
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name like any (array['therapist_profiles','profile\_%']) order by 1, 2, 3;
-- 3) Expected: only *_select_own and *_select_admin policies / Esperado: solo políticas de lectura propia y admin.
select tablename, policyname, roles, cmd from pg_policies
where schemaname = 'public' and tablename like any (array['therapist_profiles','profile\_%']) order by 1, 2;
-- 4) Expected: trigger therapist_profiles_guard enabled ('O') / Esperado: trigger habilitado ('O').
select tgname, tgenabled from pg_trigger where tgrelid = 'public.therapist_profiles'::regclass and not tgisinternal;
