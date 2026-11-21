-- Read-only checks for 20261121180000_search_order_photo_first.sql. / Comprobaciones de solo lectura.
-- Expected / esperado: order_photo_before_rates = true, old_order_gone = true, anon_can_run = true,
-- others_can_run = false, security_invoker = true, signature_count = 1
select jsonb_build_object(
  'order_photo_before_rates', pg_get_functiondef(p.oid) like '%g.is_pinned desc, (g.photo_path is not null) desc, g.rates_current desc%',
  'old_order_gone',           pg_get_functiondef(p.oid) not like '%g.rates_current desc, (g.photo_path is not null) desc%',
  'anon_can_run',            has_function_privilege('anon', p.oid, 'execute'),
  'others_can_run',          has_function_privilege('authenticated', p.oid, 'execute')
                             or has_function_privilege('service_role', p.oid, 'execute'),
  'security_invoker',        not p.prosecdef,
  'signature_count',         (select count(*) from pg_proc q join pg_namespace n on n.oid = q.pronamespace
                               where n.nspname = 'public' and q.proname = 'search_profiles')
) as verificacion
from pg_proc p
where p.oid = 'public.search_profiles(integer,integer,text,integer,integer)'::regprocedure;
