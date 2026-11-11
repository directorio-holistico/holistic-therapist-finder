-- Proves that the baseline migration removed the permissive defaults, and that explicit grants work.
-- Demuestra que la migración base quitó los permisos por defecto y que los permisos explícitos funcionan.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- Objects created by the migration role, with NO explicit grants.
-- Objetos creados por el rol de las migraciones, SIN permisos explícitos.
create table public.__probe_table (id serial primary key, note text);
create function public.__probe_fn() returns int language sql as $$ select 1 $$;

-- 1) No API role has any privilege on the new table or its sequence.
-- 1) Ningún rol de la API tiene permisos sobre la tabla nueva ni su secuencia.
do $$
declare
  r text;
  p text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege(r, 'public.__probe_table', p) then
        raise exception '% has % on a new table: default privileges were not removed', r, p;
      end if;
    end loop;
    if has_sequence_privilege(r, 'public.__probe_table_id_seq', 'USAGE')
       or has_sequence_privilege(r, 'public.__probe_table_id_seq', 'SELECT')
       or has_sequence_privilege(r, 'public.__probe_table_id_seq', 'UPDATE') then
      raise exception '% has privileges on a new sequence', r;
    end if;
  end loop;
end
$$;

-- 2) New functions are not executable by the API roles nor by PUBLIC.
--    proacl NULL would mean "PostgreSQL default" = PUBLIC can execute, so it counts as a failure.
-- 2) Las funciones nuevas no las ejecutan los roles de la API ni PUBLIC.
--    proacl NULL significaría "permiso por defecto de PostgreSQL" = PUBLIC ejecuta, y cuenta como falla.
do $$
declare
  r text;
  acl aclitem[];
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(r, 'public.__probe_fn()', 'EXECUTE') then
      raise exception '% can EXECUTE a new function', r;
    end if;
  end loop;

  select proacl into acl from pg_proc where oid = 'public.__probe_fn()'::regprocedure;
  if acl is null then
    raise exception 'new function has the default ACL: PUBLIC can execute it';
  end if;
  if exists (select 1 from aclexplode(acl) where grantee = 0 and privilege_type = 'EXECUTE') then
    raise exception 'PUBLIC can EXECUTE a new function';
  end if;
end
$$;

-- 3) As a visitor (anon), reading the new table is denied by privileges (not by RLS).
-- 3) Como visitante (anon), leer la tabla nueva se niega por permisos (no por RLS).
set local session authorization authenticator;
set local role anon;
do $$
begin
  begin
    perform 1 from public.__probe_table;
    raise exception 'anon could read a table with no grants';
  exception when insufficient_privilege then
    null; -- expected / esperado
  end;
  begin
    perform public.__probe_fn();
    raise exception 'anon could execute a function with no grants';
  exception when insufficient_privilege then
    null; -- expected / esperado
  end;
end
$$;
reset role;
reset session authorization;

-- 4) Positive control: an explicit grant works, and only for the role that received it.
-- 4) Control positivo: un permiso explícito funciona, y solo para el rol que lo recibió.
grant select on public.__probe_table to authenticated;

set local session authorization authenticator;
set local role authenticated;
do $$
begin
  perform 1 from public.__probe_table;  -- must work / debe funcionar
end
$$;
reset role;

set local role anon;
do $$
begin
  begin
    perform 1 from public.__probe_table;
    raise exception 'anon read a table that was granted only to authenticated';
  exception when insufficient_privilege then
    null; -- expected / esperado
  end;
end
$$;
reset role;
reset session authorization;

-- 5) Visitors can still use the schema (needed to read the public views later).
-- 5) Los visitantes siguen pudiendo usar el esquema (hace falta para leer las vistas públicas luego).
do $$
begin
  if not has_schema_privilege('anon', 'public', 'USAGE') then
    raise exception 'anon lost USAGE on schema public';
  end if;
end
$$;

rollback;

\echo 'OK: baseline migration removed the permissive defaults / la migración base quitó los permisos por defecto'
