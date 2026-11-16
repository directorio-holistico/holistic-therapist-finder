-- Read-only checks for the REAL project after applying 20261116010000 / Solo lectura, proyecto REAL.
-- Short names of therapies (for cards). SECURITY CHANGE: public view + public search function.
-- Nombres cortos de terapias (para tarjetas). CAMBIO DE SEGURIDAD: vista pública + función pública de búsqueda.

-- 1) The column exists and is optional. Expected / Esperado: short_name | text | YES
select column_name, data_type, is_nullable from information_schema.columns
 where table_schema = 'public' and table_name = 'therapy_translations' and column_name = 'short_name';

-- 2) Only LNT has a short name. Expected / Esperado: 1 row: LNT® - La Nueva Terapia - Método Schwiderski | LNT®
select tt.name, tt.short_name from public.therapy_translations tt where tt.short_name is not null;

-- 3) The view has the new column at the END. Expected / Esperado: last row = therapy_short_names (23 columns in total)
select ordinal_position, column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'public_profile_cards' order by ordinal_position desc limit 3;

-- 4) Grants of the search function did not change. Expected / Esperado: anon = true | authenticated = false | service_role = false
select has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as anon,
       has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as authenticated,
       has_function_privilege('service_role', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') as service_role;

-- 5) The view is still security_invoker. Expected / Esperado: security_invoker=true
select c.relname, c.reloptions from pg_class c where c.oid = 'public.public_profile_cards'::regclass;
