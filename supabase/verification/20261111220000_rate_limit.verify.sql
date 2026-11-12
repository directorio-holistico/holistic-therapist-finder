-- Read-only check for the real project / Chequeo de solo lectura para el proyecto real.
-- Expected: reveal_contact executable by NOBODY listed (only the owner); reveal_contact_limited and the purge only by service_role.
-- Esperado: reveal_contact no la ejecuta nadie de la lista (solo el dueño); reveal_contact_limited y la purga solo service_role.
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('reveal_contact', 'reveal_contact_limited', 'purge_expired_rate_limit_hits') order by 1;
-- Expected: rls_on = true, and NO grants for anon / authenticated / service_role on the table (0 rows below).
-- Esperado: rls_on = true, y NINGÚN permiso para anon / authenticated / service_role sobre la tabla (0 filas abajo).
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid = 'public.rate_limit_hits'::regclass;
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'rate_limit_hits' and grantee in ('anon', 'authenticated', 'service_role');
select count(*) as policies_on_table from pg_policy where polrelid = 'public.rate_limit_hits'::regclass;  -- expected 0
select column_name from information_schema.columns where table_schema = 'public' and table_name = 'rate_limit_hits' order by ordinal_position;
select key, value, is_public from public.app_settings where key in ('reveal_daily_limit', 'retention_rate_limit_days') order by 1;
