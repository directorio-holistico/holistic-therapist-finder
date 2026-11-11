-- Read-only checks for the REAL project after applying 20261111130000 / Solo lectura, proyecto REAL.
-- 1) Expected: EXECUTE only for authenticated on submit_revision, discard_revision, find_restricted_terms; nobody on the internal ones.
-- Esperado: EXECUTE solo authenticated en las 3 invocables; nadie en las internas.
select p.proname, p.prosecdef as security_definer, p.proconfig,
       (select string_agg(a.grantee::regrole::text, ',') from aclexplode(p.proacl) a) as grantees
from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname in ('submit_revision', 'discard_revision', 'find_restricted_terms', 'match_restricted_terms', 'add_business_days')
order by 1;
-- 2) Expected: 3 review settings with value 7, 3, 1 / Esperado: 3 ajustes con valor 7, 3, 1.
select key, value, is_public from public.app_settings where key like 'review\_days\_%' order by key;
