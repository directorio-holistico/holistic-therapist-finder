-- Read-only check for the real project after running the migration / Chequeo de solo lectura tras correr la migración.
select count(*) as profiles, count(*) filter (where display_name is null) as without_display_name from public.therapist_profiles;
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee
         where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('submit_revision', 'apply_revision_payload', 'therapist_profiles_guard')
order by 1;
