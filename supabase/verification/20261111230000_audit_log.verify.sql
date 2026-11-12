-- Read-only check for the real project / Chequeo de solo lectura para el proyecto real.
-- Expected: rls_on = true; only `authenticated` has SELECT (admin by policy); nobody has insert/update/delete/truncate.
-- Esperado: rls_on = true; solo `authenticated` tiene SELECT (el admin por política); nadie tiene insert/update/delete/truncate.
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid = 'public.audit_log'::regclass;
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'audit_log' and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC') order by 1, 2;
select polname, polcmd from pg_policy where polrelid = 'public.audit_log'::regclass;   -- expected: one SELECT policy
-- Expected: 6 audit triggers (AFTER ROW) and 2 protection triggers on audit_log.
-- Esperado: 6 triggers de auditoría (AFTER ROW) y 2 de protección en audit_log.
select tgrelid::regclass as table_name, tgname from pg_trigger
 where not tgisinternal and tgfoid in ('public.audit_row_change()'::regprocedure, 'public.audit_log_protect()'::regprocedure) order by 1, 2;
-- Expected: the two trigger functions executable by nobody in the list; the purge only by service_role.
-- Esperado: las dos funciones de trigger no las ejecuta nadie de la lista; la purga solo service_role.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('audit_row_change', 'audit_log_protect', 'purge_expired_audit_log') order by 1;
select key, value, is_public from public.app_settings where key = 'retention_audit_months';
-- Real project only: who is the role claim when the dashboard SQL editor changes data? Run a harmless update on
-- app_settings there and look at the last audit row (actor_role should be null or the editor's role).
-- Solo proyecto real: ¿qué rol figura cuando el editor SQL del panel cambia datos? Hacer un update inocuo en
-- app_settings ahí y mirar la última fila de auditoría (actor_role debería ser nulo o el rol del editor).
