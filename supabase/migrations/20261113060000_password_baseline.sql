-- Fix of current_user_has_password(): the first version assumed that a login created by email link has an EMPTY
-- encrypted_password. The real project showed it does not (Supabase stores a non-empty value), so the "choose your password"
-- gate never fired. SECURITY CHANGE: 1 table (no API access at all) and the function is replaced. Nothing else changes.
-- Corrección de current_user_has_password(): la primera versión suponía que un acceso creado por enlace tiene
-- encrypted_password VACÍO. El proyecto real mostró que no (Supabase guarda un valor no vacío), así que la puerta "elegí tu
-- contraseña" nunca se activaba. CAMBIO DE SEGURIDAD: 1 tabla (sin acceso por la API) y se reemplaza la función.
--
-- New rule (no assumption about what Supabase stores) / Regla nueva (sin suponer qué guarda Supabase):
--  * The first time the function runs for a person, it remembers a FINGERPRINT of the current password hash (SHA-256 of the
--    hash, not the hash itself). A person "has chosen a password" when the hash is DIFFERENT from that first fingerprint,
--    which can only happen if the password was really set or changed. It cannot be faked by calling an API with a flag.
--    La primera vez que corre para una persona, recuerda una HUELLA del hash actual (SHA-256 del hash, no el hash). La persona
--    "eligió una contraseña" cuando el hash es DISTINTO de esa primera huella, lo que solo pasa si realmente la puso o la
--    cambió. No se puede falsear llamando a una API con una marca.
--  * Fail closed: a person who sets a password before the first check (not possible through the website, which asks first)
--    would just be asked once more. Never the other way round.
--    Falla cerrando: quien pusiera la contraseña antes de la primera consulta (no pasa por la web, que consulta antes)
--    solo tendría que elegirla una vez más. Nunca al revés.
--  * The table has RLS on and NO grant and NO policy for any API role: nobody reads or writes it through the API, not even an
--    administrator. Only the function (SECURITY DEFINER) touches it, and only the row of auth.uid(). The row disappears when
--    the login user is deleted (erasure). The fingerprint is not reversible and is not personal data on its own.
--    La tabla tiene RLS y NINGÚN permiso ni política para roles de la API: nadie la lee ni la escribe por la API, ni un
--    admin. Solo la función (SECURITY DEFINER) la toca, y solo la fila de auth.uid(). La fila se borra al borrar el usuario.

create table public.password_baselines (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  baseline     text not null check (baseline ~ '^[0-9a-f]{64}$'),
  created_at   timestamptz not null default now()
);
comment on table public.password_baselines is
  'First fingerprint (SHA-256) of each login''s password hash; a different hash later = the person chose a password. No API access / Primera huella del hash de cada acceso; un hash distinto después = la persona eligió contraseña. Sin acceso por la API.';
alter table public.password_baselines enable row level security;
revoke all on public.password_baselines from public, anon, authenticated, service_role;

-- VOLATILE on purpose: it may write the first fingerprint. / VOLATILE a propósito: puede escribir la primera huella.
create or replace function public.current_user_has_password()
returns boolean
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $$
declare
  uid     uuid := auth.uid();
  current text;
  first   text;
begin
  if uid is null then
    return false;
  end if;
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(u.encrypted_password, ''), 'UTF8')), 'hex')
    into current
    from auth.users u where u.id = uid;
  if current is null then
    return false;  -- unknown login: nothing to remember / acceso desconocido: nada que recordar
  end if;

  insert into public.password_baselines (auth_user_id, baseline) values (uid, current)
    on conflict (auth_user_id) do nothing;
  select b.baseline into first from public.password_baselines b where b.auth_user_id = uid;
  return current is distinct from first;
end
$$;

revoke execute on function public.current_user_has_password() from public, anon, service_role;
grant execute on function public.current_user_has_password() to authenticated;
