-- Read-only check for the real project / Chequeo de solo lectura para el proyecto real.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('reveal_contact', 'purge_expired_contact_reveals') order by 1;
select key, value, is_public from public.app_settings where key = 'retention_contact_reveals_months';
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid = 'public.contact_reveals'::regclass;
