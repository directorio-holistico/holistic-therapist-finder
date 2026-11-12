-- Read-only check for the real project / Chequeo de solo lectura para el proyecto real.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('report_profile', 'close_report', 'suspend_profile', 'reinstate_profile', 'purge_expired_reports') order by 1;
select c.relname, c.relrowsecurity as rls_on from pg_class c
 where c.oid in ('public.reports'::regclass, 'public.report_reasons'::regclass, 'public.report_statuses'::regclass) order by 1;
select code from public.report_reasons order by sort_order;
select code from public.report_statuses order by sort_order;
select key, value, is_public from public.app_settings where key = 'retention_reports_months';
