-- Read-only check for the real project after running the migration / Chequeo de solo lectura tras correr la migración.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee
         where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('search_profiles', 'log_search', 'purge_expired_unmet_searches')
order by 1;
select key, value, is_public from public.app_settings where key = 'retention_unmet_searches_months';
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid = 'public.unmet_searches'::regclass;
