-- Read-only checks for the REAL project after applying 20261113020000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: instagram | f (public) | 4 ; view has the column "instagram"; anon keeps SELECT on the view only.
select code, is_private, sort_order from public.contact_types order by sort_order;
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'public_profile_detail' and column_name in ('instagram', 'website', 'therapies_detail');
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'public_profile_detail' and grantee in ('anon', 'authenticated') order by grantee;
