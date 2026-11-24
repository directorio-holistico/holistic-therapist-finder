-- Read-only checks for the REAL project after applying 20261124130000 / Solo lectura, proyecto REAL.
-- 1) Expected: 2 audit triggers (audit_therapies, audit_therapy_translations). / Esperado: 2 triggers de auditoría.
select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and t.tgname in ('audit_therapies', 'audit_therapy_translations') order by 1;
-- 2) Expected: both functions exist; anon_can = false; auth_can = true (the admin check is inside the function).
-- 2) Esperado: las dos funciones existen; anon_can = false; auth_can = true (el chequeo de admin va dentro de la función).
select p.proname, has_function_privilege('anon', p.oid, 'execute') as anon_can, has_function_privilege('authenticated', p.oid, 'execute') as auth_can,
       p.prosecdef as security_definer
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('admin_add_therapy', 'admin_set_therapy_active') order by 1;
-- 3) Expected: the catalog tables still have NO insert / update / delete for anon or authenticated (0 rows).
-- 3) Esperado: las tablas del catálogo siguen SIN insert / update / delete para anon ni authenticated (0 filas).
select table_name, grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name in ('therapies', 'therapy_translations')
   and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT';
