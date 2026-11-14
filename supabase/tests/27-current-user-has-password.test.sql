-- current_user_has_password(): yes/no about the caller only; closed to anon; false without a session.
-- current_user_has_password(): sí/no solo sobre quien llama; cerrada a anon; falso sin sesión.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at, encrypted_password) values
  ('00000000-0000-0000-0000-0000000010a1', 'sin@example.test', now(), ''),                       -- logged in by link, no password
  ('00000000-0000-0000-0000-0000000010b2', 'con@example.test', now(), '$2a$10$fakehashfakehash'); -- has a password

-- anon cannot call it / anon no puede llamarla
set session authorization authenticator;
set role anon;
do $$
begin
  begin
    perform public.current_user_has_password();
    raise exception 'anon was allowed to call current_user_has_password';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- each caller sees only their own answer / cada quien ve solo su respuesta
do $$
declare
  r boolean;
begin
  set local session authorization authenticator;
  set local role authenticated;

  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'a login without password must answer false, got %', r; end if;

  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010b2","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from true then raise exception 'a login with a password must answer true, got %', r; end if;

  -- a session of a user that does not exist in auth -> false (never an error, never someone else's answer)
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010ff","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'unknown user must answer false, got %', r; end if;

  -- no sub at all -> false
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'no session must answer false, got %', r; end if;

  reset role;
  reset session authorization;
end
$$;

-- the function takes no parameter, so it cannot be pointed at another person / no recibe parámetros
do $$
begin
  if (select pronargs from pg_proc where proname = 'current_user_has_password' and pronamespace = 'public'::regnamespace) <> 0 then
    raise exception 'current_user_has_password must take no parameters';
  end if;
end
$$;

rollback;
select 'OK 27-current-user-has-password' as result;
