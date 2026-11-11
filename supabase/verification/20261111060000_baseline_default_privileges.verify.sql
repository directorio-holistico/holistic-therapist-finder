-- Verification queries for the baseline migration, to run on a REAL Supabase project.
-- Consultas de verificación de la migración base, para correr en un proyecto REAL de Supabase.
--
-- Run them BEFORE and AFTER the migration and compare. Read-only: they change nothing.
-- Correrlas ANTES y DESPUÉS de la migración y comparar. Solo lectura: no cambian nada.

-- Default privileges configured for the role that runs migrations.
-- Permisos por defecto configurados para el rol que corre las migraciones.
-- kind / tipo: r = tables, S = sequences, f = functions.
select
  r.rolname                      as creator_role,
  coalesce(n.nspname, '(all)')   as schema,
  d.defaclobjtype                as kind,
  d.defaclacl::text              as default_acl
from pg_default_acl d
join pg_roles r on r.oid = d.defaclrole
left join pg_namespace n on n.oid = d.defaclnamespace
where r.rolname = 'postgres'
order by schema, kind;

-- EXPECTED AFTER THE MIGRATION / ESPERADO DESPUÉS DE LA MIGRACIÓN:
--   * rows for schema public, kinds r, S and f: they may DISAPPEAR (PostgreSQL deletes a default
--     entry when it equals the built-in default, which is correct). If a row is still there,
--     default_acl must NOT contain anon=, authenticated= or service_role= entries.
--   * the (all) row for kind f must exist and must NOT contain an entry that starts with "=X/"
--     (that entry is PUBLIC executing functions). Expected: {postgres=X/postgres}.
--   * filas del esquema public, tipos r, S y f: pueden DESAPARECER (PostgreSQL borra la entrada
--     cuando queda igual al permiso por defecto integrado, y eso es correcto). Si alguna sigue,
--     default_acl NO debe tener entradas anon=, authenticated= ni service_role=.
--   * la fila (all) del tipo f debe existir y NO debe tener una entrada que empiece con "=X/"
--     (esa entrada es PUBLIC ejecutando funciones). Esperado: {postgres=X/postgres}.

-- Existing tables in public that the API roles can already touch (should be empty on a new project).
-- Tablas existentes en public que los roles de la API ya pueden tocar (debería estar vacío en un proyecto nuevo).
select table_schema, table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;
