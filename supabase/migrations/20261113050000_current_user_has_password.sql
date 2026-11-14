-- current_user_has_password(): tells the logged-in person's own session whether their login already has a password.
-- SECURITY CHANGE: 1 function (SECURITY DEFINER because it reads the auth schema). Nothing else changes.
-- current_user_has_password(): le dice a la sesión de la persona ingresada si su acceso ya tiene contraseña.
-- CAMBIO DE SEGURIDAD: 1 función (SECURITY DEFINER porque lee el esquema auth). No cambia nada más.
--
-- Why / Por qué:
--  * The sign-up decision (37): first login by email link, then the person MUST choose a password (10+ characters) before
--    using the account. The website needs to know "has this person chosen one yet?". Supabase does not expose it to the API.
--    La decisión 37: primer ingreso por enlace al mail; luego la persona DEBE elegir una contraseña (10+ caracteres) antes de
--    usar la cuenta. La web necesita saber si ya la eligió. Supabase no lo expone por la API.
--  * It answers only a yes/no about the CALLER (auth.uid()): it takes no parameter, so it cannot be used to look at anybody
--    else, and it never returns the hash (only whether the column is empty).
--    Responde solo sí/no sobre QUIEN LLAMA (auth.uid()): no recibe parámetros, así que no sirve para mirar a otra persona, y
--    nunca devuelve el hash (solo si la columna está vacía).
--  * A login created by email link has an empty encrypted_password until the person sets one [INFERRED: confirmed by the
--    verification script on the real project, see the .verify.sql file].
--    Un acceso creado por enlace al mail tiene encrypted_password vacío hasta que la persona elige una [INFERIDO: lo confirma
--    el script de verificación en el proyecto real, ver el .verify.sql].
--  * Fixed search_path, no EXECUTE for public/anon/service_role, EXECUTE only for authenticated. Nobody logged in -> false.
--    search_path fijo, sin EXECUTE para public/anon/service_role, solo authenticated. Sin sesión -> falso.

create function public.current_user_has_password()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((
    select coalesce(u.encrypted_password, '') <> ''
    from auth.users u
    where u.id = auth.uid()
  ), false)
$$;

revoke execute on function public.current_user_has_password() from public, anon, service_role;
grant execute on function public.current_user_has_password() to authenticated;
