-- Read-only checks for the REAL project after applying 20261112170000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: 2 new columns, 3 functions for logged-in users (SECURITY DEFINER), 1 helper for visitors,
-- the setting rates_validity_months = 6, and search_profiles ending in the 3 new columns.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'therapist_profiles' and column_name in ('rates_confirmed_at', 'is_pinned')
order by column_name;

select p.proname, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('update_my_rates', 'confirm_my_rates', 'set_profile_pinned', 'rates_validity_months', 'search_profiles')
order by p.proname;

select key, value, is_public from public.app_settings where key = 'rates_validity_months';

select count(*) as search_result_columns from information_schema.columns
where table_schema = 'public' and table_name = 'public_profile_cards';
