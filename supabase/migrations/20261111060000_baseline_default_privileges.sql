-- Baseline migration: remove the permissive default privileges.
-- Migración base: quita los permisos por defecto demasiado permisivos.
--
-- SECURITY CHANGE / CAMBIO DE SEGURIDAD: yes / sí.
--
-- Why / Por qué:
--   A classic Supabase project grants ALL on every new table, sequence and function in schema
--   `public` to anon, authenticated and service_role, and PostgreSQL lets PUBLIC execute every new
--   function. This project's rule is the opposite: every object declares its own grants, in the
--   same migration that creates it. After this migration, a new object has NO access for anyone
--   except its owner, until a migration grants it explicitly.
--   Un proyecto clásico de Supabase otorga ALL sobre toda tabla, secuencia y función nueva del
--   esquema `public` a anon, authenticated y service_role, y PostgreSQL deja que PUBLIC ejecute
--   toda función nueva. La regla de este proyecto es la contraria: cada objeto declara sus
--   permisos, en la misma migración que lo crea. Después de esta migración, un objeto nuevo no
--   tiene acceso para nadie salvo su dueño, hasta que una migración lo otorgue de forma explícita.
--
-- Scope / Alcance:
--   Default privileges are per creating role. Migrations run as `postgres`, so that is the role
--   configured here. Objects created by other roles (for example Supabase's own extensions) are
--   not affected.
--   Los permisos por defecto son por rol creador. Las migraciones corren como `postgres`, por eso
--   se configura ese rol. Los objetos creados por otros roles (por ejemplo las extensiones propias
--   de Supabase) no se ven afectados.
--
-- This migration is idempotent: running it twice leaves the same result.
-- Esta migración es idempotente: correrla dos veces deja el mismo resultado.

-- 1) Tables / Tablas
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;

-- 2) Sequences / Secuencias
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

-- 3) Functions: not executable by the API roles by default.
-- 3) Funciones: los roles de la API no las ejecutan por defecto.
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;

-- 4) Functions: PUBLIC must not execute new functions by default (in any schema).
--    This one is NOT limited to `public`: PostgreSQL's built-in default is global.
-- 4) Funciones: PUBLIC no ejecuta funciones nuevas por defecto (en cualquier esquema).
--    Esta NO se limita a `public`: el permiso por defecto de PostgreSQL es global.
alter default privileges for role postgres
  revoke execute on functions from public;
