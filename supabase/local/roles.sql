-- Local emulation of the Supabase roles and the `auth` helpers, for migration tests only.
-- Emulación local de los roles de Supabase y de las funciones de `auth`, solo para probar migraciones.
--
-- NEVER run this against a real Supabase project: Supabase already provides all of this.
-- NUNCA ejecutar esto en un proyecto real de Supabase: Supabase ya trae todo esto.
--
-- Roles (as in Supabase):
--   anon           - not logged in (a visitor). No login of its own; PostgREST switches to it.
--   authenticated  - logged-in user (a therapist or an admin).
--   service_role   - server-only key; bypasses RLS.
--   authenticator  - the login role the API connects with; it switches to the roles above.
-- Roles (como en Supabase): anon = visitante sin sesión; authenticated = usuario con sesión;
-- service_role = clave solo de servidor, ignora RLS; authenticator = rol con el que se conecta
-- la API y desde el cual cambia a los anteriores.
--
-- No passwords are created here. Tests impersonate roles with SET SESSION AUTHORIZATION / SET ROLE.
-- Acá no se crean contraseñas. Las pruebas suplantan roles con SET SESSION AUTHORIZATION / SET ROLE.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    -- Login role without a password: it cannot be used to connect; it exists so that
    -- `session_user` can be emulated exactly as the API sees it.
    -- Rol con login pero sin contraseña: no sirve para conectarse; existe para emular
    -- `session_user` tal como lo ve la API.
    create role authenticator noinherit login;
  end if;
end
$$;

grant anon, authenticated, service_role to authenticator;

-- Minimal `auth` schema. Supabase provides the real one; this stub only has what our policies need.
-- Esquema `auth` mínimo. Supabase trae el real; este solo tiene lo que necesitan nuestras políticas.
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz,
  -- like the real table: empty text = never set a password (a login created by email link) / como la real: vacío = nunca puso contraseña
  encrypted_password text not null default '',
  created_at timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;

-- Same starting point as a classic Supabase project: roles can use the public schema and
-- new objects in it are granted to the three roles by default. This is deliberately permissive:
-- the baseline migration (next commit) must REVOKE it, and the tests must prove that it did.
-- Mismo punto de partida que un proyecto clásico de Supabase: los roles usan el esquema public y
-- los objetos nuevos se les otorgan por defecto. Es permisivo a propósito: la migración base
-- (próximo commit) debe revocarlo y las pruebas deben demostrar que lo hizo.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
