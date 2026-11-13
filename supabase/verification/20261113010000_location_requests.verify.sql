-- Read-only checks for the REAL project after applying 20261113010000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: rls=true; anon and authenticated privileges as listed; 5 policies; 1 trigger guard + 1 audit trigger.
select c.relname, c.relrowsecurity as rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'location_requests';
select grantee, privilege_type, string_agg(column_name, ',') as columns
  from information_schema.column_privileges
 where table_schema = 'public' and table_name = 'location_requests' and grantee in ('anon', 'authenticated')
 group by grantee, privilege_type order by grantee, privilege_type;
select policyname, cmd, roles from pg_policies where schemaname = 'public' and tablename = 'location_requests' order by policyname;
select tgname from pg_trigger where tgrelid = 'public.location_requests'::regclass and not tgisinternal order by tgname;
select p.proname, has_function_privilege('anon', p.oid, 'execute') as anon_can, has_function_privilege('authenticated', p.oid, 'execute') as auth_can
  from pg_proc p where p.proname in ('resolve_location_request', 'location_requests_guard') and p.pronamespace = 'public'::regnamespace;
