-- Read-only check for the real project after running the migration / Chequeo de solo lectura tras correr la migración.
-- 1) both views must be security_invoker / las dos vistas deben ser security_invoker
select c.relname, c.reloptions from pg_class c where c.relname in ('public_profile_cards', 'public_profile_detail') and c.relnamespace = 'public'::regnamespace;
-- 2) everything anon can read in public (table level and column level) / todo lo que anon lee en public
select 'table' as level, table_name, null as column_name, privilege_type from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public'
union all
select 'column', table_name, column_name, privilege_type from information_schema.role_column_grants where grantee = 'anon' and table_schema = 'public'
order by 1, 2, 3;
-- 3) the columns of the views: no phone, no email / las columnas de las vistas
select table_name, column_name from information_schema.columns where table_schema = 'public' and table_name in ('public_profile_cards', 'public_profile_detail') order by 1, ordinal_position;
