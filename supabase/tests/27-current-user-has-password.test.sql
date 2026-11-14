-- current_user_has_password(): "has this login chosen a password?" = the password hash changed since the first check.
-- Yes/no about the caller only; closed to anon; the baseline table is closed to every API role; false without a session.
-- current_user_has_password(): "¿este acceso eligió una contraseña?" = el hash cambió desde la primera consulta.
-- Sí/no solo sobre quien llama; cerrada a anon; la tabla de base cerrada a todos los roles de la API; falso sin sesión.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- 'link' models REAL Supabase: a login created by email link already has a NON-EMPTY hash (it was wrong to assume empty).
insert into auth.users (id, email, email_confirmed_at, encrypted_password) values
  ('00000000-0000-0000-0000-0000000010a1', 'link@example.test', now(), '$2a$10$randomhashcreatedbytheauthservice1'),
  ('00000000-0000-0000-0000-0000000010b2', 'other@example.test', now(), '$2a$10$anotherrandomhashfromtheauthservice');

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

do $$
declare
  r boolean;
begin
  set local session authorization authenticator;
  set local role authenticated;

  -- 1) first check of A: has NOT chosen a password yet, even though the hash is non-empty
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'a login that never chose a password must answer false, got %', r; end if;
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'asking twice must not change the answer, got %', r; end if;

  -- the table is closed to the API role: no select, no insert, no update, no delete
  begin perform 1 from public.password_baselines; raise exception 'authenticated could read password_baselines';
  exception when insufficient_privilege then null; end;
  begin insert into public.password_baselines (auth_user_id, baseline) values ('00000000-0000-0000-0000-0000000010b2', repeat('a', 64));
    raise exception 'authenticated could write password_baselines';
  exception when insufficient_privilege then null; end;

  reset role;
  reset session authorization;
end
$$;

-- A really sets a password: the hash changes (the auth service does this) / A pone una contraseña: cambia el hash
update auth.users set encrypted_password = '$2a$10$thehashofthepasswordtheuserchose0001' where id = '00000000-0000-0000-0000-0000000010a1';

do $$
declare
  r boolean;
begin
  set local session authorization authenticator;
  set local role authenticated;

  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from true then raise exception 'after the hash changed it must answer true, got %', r; end if;

  -- B is untouched by A's change (each caller sees only their own answer)
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010b2","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'B never chose a password, must answer false, got %', r; end if;

  -- an unknown login and a session without sub -> false, never an error
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000010ff","role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'unknown user must answer false, got %', r; end if;
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  r := public.current_user_has_password();
  if r is distinct from false then raise exception 'no session must answer false, got %', r; end if;

  reset role;
  reset session authorization;
end
$$;

do $$
begin
  -- one baseline row per known login that asked (A and B); none for the unknown one
  if (select count(*) from public.password_baselines) <> 2 then raise exception 'expected exactly 2 baseline rows'; end if;
  -- the hash itself is never stored, only its fingerprint
  if exists (select 1 from public.password_baselines where baseline like '$2%') then raise exception 'a hash was stored'; end if;
  if (select pronargs from pg_proc where proname = 'current_user_has_password' and pronamespace = 'public'::regnamespace) <> 0 then
    raise exception 'current_user_has_password must take no parameters';
  end if;
  -- deleting the login removes its baseline (erasure)
  delete from auth.users where id = '00000000-0000-0000-0000-0000000010b2';
  if (select count(*) from public.password_baselines) <> 1 then raise exception 'the baseline must go with the login'; end if;
end
$$;

rollback;
select 'OK 27-current-user-has-password' as result;
