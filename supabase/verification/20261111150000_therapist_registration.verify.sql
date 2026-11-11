-- Read-only check for the real project after running the migration / Chequeo de solo lectura tras correr la migración.
select code, is_required, is_active from public.legal_document_types order by sort_order;
select c.relname, c.relrowsecurity as rls_on from pg_class c where c.oid in ('public.terms_acceptances'::regclass, 'public.legal_document_types'::regclass);
select p.proname, p.prosecdef as security_definer, p.proconfig as config,
       (select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ' order by coalesce(r.rolname, 'PUBLIC'))
          from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          left join pg_roles r on r.oid = a.grantee
         where a.privilege_type = 'EXECUTE') as can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('register_therapist', 'set_offers_consent', 'terms_acceptances_guard')
order by 1;
-- Supabase Auth must fill auth.users.email_confirmed_at when the user opens the email link (check with a real sign-in):
-- Supabase Auth debe completar auth.users.email_confirmed_at al abrir el enlace del mail (comprobar con un acceso real):
select count(*) filter (where email_confirmed_at is not null) as confirmed, count(*) as total from auth.users;
