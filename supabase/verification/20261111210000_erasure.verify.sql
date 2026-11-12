-- Read-only check for the real project / Chequeo de solo lectura para el proyecto real.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('parse_fingerprints', 'erasure_material', 'erase_therapist', 'check_erasure_fingerprints', 'purge_expired_erasure_fingerprints') order by 1;
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid = 'public.erasure_fingerprints'::regclass;
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'erasure_fingerprints' and grantee in ('anon', 'authenticated', 'PUBLIC');  -- expected: no rows / esperado: ninguna fila
select key, value, is_public from public.app_settings where key = 'retention_erasure_fingerprints_months';
