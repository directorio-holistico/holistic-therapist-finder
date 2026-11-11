-- Checks that the local environment behaves like the real thing. Any failure raises an exception.
-- Verifica que el entorno local se comporte como el real. Cualquier falla lanza una excepción.
-- Run with / Ejecutar con: scripts/db/Test-LocalDb.ps1

begin;

-- 0) The database is UTF-8, like Supabase (Spanish Windows creates WIN1252 databases by default).
-- 0) La base es UTF-8, como Supabase (Windows en español crea bases WIN1252 por defecto).
do $$
begin
  if current_setting('server_encoding') <> 'UTF8' then
    raise exception 'database encoding must be UTF8, got %', current_setting('server_encoding');
  end if;
end
$$;

-- 1) The roles exist and have the right attributes.
-- 1) Los roles existen y tienen los atributos correctos.
do $$
declare
  r record;
begin
  for r in
    select rolname, rolsuper, rolbypassrls, rolcanlogin
    from pg_roles
    where rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
  loop
    if r.rolsuper then
      raise exception 'role % must not be superuser', r.rolname;
    end if;
    if r.rolname = 'service_role' and not r.rolbypassrls then
      raise exception 'service_role must bypass RLS';
    end if;
    if r.rolname in ('anon', 'authenticated') and r.rolbypassrls then
      raise exception 'role % must not bypass RLS', r.rolname;
    end if;
    if r.rolname in ('anon', 'authenticated', 'service_role') and r.rolcanlogin then
      raise exception 'role % must not have login', r.rolname;
    end if;
  end loop;

  if (select count(*) from pg_roles
      where rolname in ('anon', 'authenticated', 'service_role', 'authenticator')) <> 4 then
    raise exception 'one or more roles are missing';
  end if;
end
$$;

-- 2) Visitors and users cannot create objects in the public schema.
-- 2) Visitantes y usuarios no pueden crear objetos en el esquema public.
do $$
begin
  if has_schema_privilege('anon', 'public', 'CREATE') then
    raise exception 'anon must not be able to CREATE in schema public';
  end if;
  if has_schema_privilege('authenticated', 'public', 'CREATE') then
    raise exception 'authenticated must not be able to CREATE in schema public';
  end if;
end
$$;

-- 3) The API identity is emulated exactly: session_user is the authenticator, current_user the role.
-- 3) La identidad de la API se emula exacta: session_user es authenticator, current_user es el rol.
set local session authorization authenticator;
set local role anon;
do $$
begin
  if session_user <> 'authenticator' then
    raise exception 'session_user should be authenticator, got %', session_user;
  end if;
  if current_user <> 'anon' then
    raise exception 'current_user should be anon, got %', current_user;
  end if;
  if auth.uid() is not null then
    raise exception 'auth.uid() must be null for a visitor';
  end if;
end
$$;
reset role;
reset session authorization;

-- 4) auth.uid() reads the JWT claim, as in Supabase.
-- 4) auth.uid() lee el claim del JWT, como en Supabase.
set local session authorization authenticator;
set local role authenticated;
select set_config('request.jwt.claims',
                  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
do $$
begin
  if auth.uid() is distinct from '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'auth.uid() did not return the claim, got %', auth.uid();
  end if;
  if auth.role() <> 'authenticated' then
    raise exception 'auth.role() should be authenticated, got %', auth.role();
  end if;
end
$$;
reset role;
reset session authorization;

-- 5) The permissive Supabase defaults are present on purpose: a table created now is readable by anon.
-- The baseline migration must remove this. When it exists, this check is replaced by its opposite.
-- 5) Los permisos permisivos de Supabase están a propósito: una tabla creada ahora la lee anon.
-- La migración base debe quitarlos. Cuando exista, esta verificación se reemplaza por la opuesta.
create table public.__probe_default_privileges (id int);
do $$
begin
  if not has_table_privilege('anon', 'public.__probe_default_privileges', 'SELECT') then
    raise exception 'expected the permissive default privileges to be present before the baseline migration';
  end if;
end
$$;

rollback;

\echo 'OK: local roles and auth helpers behave as expected / roles locales y funciones de auth correctos'
