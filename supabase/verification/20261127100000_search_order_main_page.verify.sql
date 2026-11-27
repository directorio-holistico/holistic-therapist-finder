-- Verification of 20261127100000_search_order_main_page / Verificación de 20261127100000_search_order_main_page
-- 1) The function keeps its safety settings (expected: security_definer = false, anon = true, authenticated = false).
select (select prosecdef from pg_proc where oid = 'public.search_profiles(integer,integer,text,integer,integer)'::regprocedure) as security_definer,
       has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as anon_can_run,
       has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as authenticated_can_run;

-- 2) Unfiltered: inside the same photo / current-prices tier the approval date must go DOWN (newest first). Expected: bad_pairs = 0.
with r as (
  select row_number() over () as pos, display_name, photo_path is not null as has_photo, rates_current, is_pinned, approved_at
  from public.search_profiles(null, null, null, 50, 0))
select count(*) as bad_pairs
from r a join r b on b.pos = a.pos + 1
where a.is_pinned = b.is_pinned and a.has_photo = b.has_photo and a.rates_current = b.rates_current and a.approved_at < b.approved_at;

-- 3) Look at it with your eyes: first rows of the main page. / Para mirar: las primeras filas de la página principal.
select display_name, photo_path is not null as has_photo, rates_current, is_pinned, approved_at
from public.search_profiles(null, null, null, 50, 0);
