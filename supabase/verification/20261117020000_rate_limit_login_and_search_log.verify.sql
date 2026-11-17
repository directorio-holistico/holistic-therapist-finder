-- Read-only checks for the REAL project after applying 20261117020000 / Solo lectura, proyecto REAL.
-- Daily limit per origin for sign-in and the unmet-search log. SECURITY CHANGE: 2 functions, 3 settings, log_search closed.

-- 1) Both functions are security definer with a fixed search_path. Expected / Esperado: 2 rows | true | {search_path=pg_catalog, public}
select p.proname, p.prosecdef as security_definer, p.proconfig
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('rate_limit_hit', 'log_search_limited')
 order by p.proname;

-- 2) Who can execute. Expected / Esperado:
--    rate_limit_hit, log_search_limited: anon false | authenticated false | service_role true
--    log_search (the direct door): false | false | false
select f.name,
       has_function_privilege('anon', f.sig, 'execute') as anon,
       has_function_privilege('authenticated', f.sig, 'execute') as authenticated,
       has_function_privilege('service_role', f.sig, 'execute') as service_role
  from (values ('rate_limit_hit', 'public.rate_limit_hit(text, text)'),
               ('log_search_limited', 'public.log_search_limited(integer, integer, text, text)'),
               ('log_search', 'public.log_search(integer, integer, text)')) f(name, sig)
 order by f.name;

-- 3) The three settings exist, are private and have the default values. Expected / Esperado: login_daily_limit 30 | login_link_daily_limit 10 | unmet_search_daily_limit 50, is_public false
select key, value, is_public from public.app_settings
 where key in ('login_daily_limit', 'login_link_daily_limit', 'unmet_search_daily_limit') order by key;

-- 4) The counters table has RLS and no API role can touch it. Expected / Esperado: true | false | false
select c.relrowsecurity as rls,
       has_table_privilege('anon', 'public.rate_limit_hits', 'select') as anon_can_read,
       has_table_privilege('authenticated', 'public.rate_limit_hits', 'select') as authenticated_can_read
  from pg_class c where c.oid = 'public.rate_limit_hits'::regclass;
