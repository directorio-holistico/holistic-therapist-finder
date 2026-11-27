-- Verification of 20261127110000_search_order_daily_rotation / Verificación de 20261127110000_search_order_daily_rotation
-- 1) Safety settings (expected: false, true, false). / Permisos (esperado: false, true, false).
select (select prosecdef from pg_proc where oid = 'public.search_profiles(integer,integer,text,integer,integer)'::regprocedure) as security_definer,
       has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as anon_can_run,
       has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as authenticated_can_run;

-- 2) Unfiltered: inside the same pin / photo / current-prices tier, the hash of today must go UP. Expected: bad_pairs = 0.
with r as (
  select row_number() over () as pos, profile_id, photo_path is not null as has_photo, rates_current, is_pinned, result_group
  from public.search_profiles(null, null, null, 50, 0)),
k as (
  select *, md5(profile_id::text || ((now() at time zone 'America/Argentina/Buenos_Aires')::date)::text) as h from r)
select count(*) as bad_pairs
from k a join k b on b.pos = a.pos + 1
where a.result_group = b.result_group and a.is_pinned = b.is_pinned and a.has_photo = b.has_photo and a.rates_current = b.rates_current and a.h > b.h;

-- 3) With a filter the old rule holds (oldest approval first inside the tier). Expected: bad_pairs = 0.
with r as (
  select row_number() over () as pos, photo_path is not null as has_photo, rates_current, is_pinned, result_group, approved_at
  from public.search_profiles(null, null, 'remote', 50, 0))
select count(*) as bad_pairs
from r a join r b on b.pos = a.pos + 1
where a.result_group = b.result_group and a.is_pinned = b.is_pinned and a.has_photo = b.has_photo and a.rates_current = b.rates_current and a.approved_at > b.approved_at;
