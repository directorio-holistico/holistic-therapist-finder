-- Read-only checks for 20261117050000. Run each query on its own. / Consultas de solo lectura; correr cada una por separado.

-- 1. Expected: 2 rows (therapist_profiles.about, profile_therapies.description). / Esperado: 2 filas.
select table_name, column_name from information_schema.columns
where table_schema = 'public' and ((table_name = 'therapist_profiles' and column_name = 'about') or (table_name = 'profile_therapies' and column_name = 'description'))
order by table_name;

-- 2. Expected: 2 constraints. / Esperado: 2 restricciones.
select conname from pg_constraint where conname in ('therapist_profiles_about_check', 'profile_therapies_description_check') order by conname;

-- 3. Expected: 3 rows (the 2 new columns plus the view column public_profile_detail.about). / Esperado: 3 filas (las 2 columnas nuevas y la columna de la vista).
select table_name, column_name from information_schema.role_column_grants
where grantee = 'anon' and table_schema = 'public' and column_name in ('about', 'description') order by table_name;

-- 4. Expected: contains_contact_data -> anon false, authenticated true; validate_profile_texts -> false, false.
-- Esperado: contains_contact_data -> anon false, authenticated true; validate_profile_texts -> false, false.
select 'contains_contact_data' as funcion, has_function_privilege('anon', 'public.contains_contact_data(text)', 'execute') as anon,
       has_function_privilege('authenticated', 'public.contains_contact_data(text)', 'execute') as authenticated
union all
select 'validate_profile_texts', has_function_privilege('anon', 'public.validate_profile_texts(jsonb)', 'execute'),
       has_function_privilege('authenticated', 'public.validate_profile_texts(jsonb)', 'execute');

-- 5. Expected: the last column of the detail view is "about". / Esperado: la última columna de la vista de detalle es "about".
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'public_profile_detail' order by ordinal_position desc limit 1;
