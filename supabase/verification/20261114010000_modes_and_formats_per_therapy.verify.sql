-- Read-only checks for the REAL project after applying 20261114010000 / Solo lectura, proyecto REAL.
-- Modes and formats now belong to each therapy. / La modalidad y el formato ahora pertenecen a cada terapia.

-- 1) Old tables gone, new tables with RLS. Expected / Esperado: old_modes = null | old_formats = null | rls_modes = t | rls_formats = t
select to_regclass('public.profile_service_modes')   as old_modes,
       to_regclass('public.profile_session_formats') as old_formats,
       (select c.relrowsecurity from pg_class c where c.oid = 'public.profile_therapy_service_modes'::regclass)   as rls_modes,
       (select c.relrowsecurity from pg_class c where c.oid = 'public.profile_therapy_session_formats'::regclass) as rls_formats;

-- 2) Table privileges. Expected / Esperado: ONLY "authenticated | SELECT" on each table (4 rows in total). Nothing for anon
--    (it reads by column, see 3), nothing for service_role, no INSERT/UPDATE/DELETE for anybody.
select table_name, grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('profile_therapy_service_modes', 'profile_therapy_session_formats')
   and grantee in ('anon', 'authenticated', 'service_role')
 order by table_name, grantee, privilege_type;

-- 3) Columns anon can read. Expected / Esperado: exactly 6 rows (3 per table: profile_id, therapy_id and the mode/format id), all SELECT.
select table_name, column_name, privilege_type from information_schema.role_column_grants
 where table_schema = 'public' and grantee = 'anon'
   and table_name in ('profile_therapy_service_modes', 'profile_therapy_session_formats')
 order by table_name, column_name;

-- 4) Policies. Expected / Esperado: 6 rows, all SELECT: select_admin and select_own (authenticated), select_public (anon), per table.
select tablename, policyname, cmd, roles from pg_policies
 where schemaname = 'public' and tablename in ('profile_therapy_service_modes', 'profile_therapy_session_formats')
 order by tablename, policyname;

-- 5) The "at least one" rule: 3 deferred constraint triggers. Expected / Esperado: 3 rows, deferrable = t, initially_deferred = t.
select c.relname as table_name, t.tgname, t.tgdeferrable as deferrable, t.tginitdeferred as initially_deferred
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where t.tgisinternal = false and t.tgname like '%options_check' and c.relnamespace = 'public'::regnamespace
 order by c.relname;

-- 6) Functions. Expected / Esperado: apply_revision_payload security_definer = f, anon f, authenticated f (as before) | the check function: f, f, f
--    | search_profiles: security_definer f, anon t, authenticated f | submit_revision: security_definer t, anon f, authenticated t (as before).
select p.proname, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('apply_revision_payload', 'profile_therapy_options_check', 'search_profiles', 'submit_revision')
 order by p.proname;

-- 7) Therapies that lack a mode or a format (data from before this rule). Expected / Esperado: 0 rows.
--    If something shows up, edit that profile (or delete the test data) and send it to review again.
select pt.profile_id, pt.therapy_id,
       not exists (select 1 from public.profile_therapy_service_modes x where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id) as no_mode,
       not exists (select 1 from public.profile_therapy_session_formats x where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id) as no_format
  from public.profile_therapies pt
 where not exists (select 1 from public.profile_therapy_service_modes x where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id)
    or not exists (select 1 from public.profile_therapy_session_formats x where x.profile_id = pt.profile_id and x.therapy_id = pt.therapy_id);

-- 8) Open revisions still in the OLD shape (lists outside the therapies). Expected / Esperado: 0.
select count(*) as open_revisions_in_old_shape from public.profile_revisions
 where closed_at is null and (payload ? 'service_modes' or payload ? 'session_formats');
