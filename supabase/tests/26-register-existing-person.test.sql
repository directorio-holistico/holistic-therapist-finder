-- register_therapist for a person who already exists without a profile (an administrator who is not yet a therapist).
-- register_therapist para una persona que ya existe sin perfil (un administrador que todavía no es terapeuta).
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000009a1', 'adm@example.test', now()),   -- admin without a profile
  ('00000000-0000-0000-0000-0000000009b2', 'ter@example.test', now());   -- therapist with a profile
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000009a1', '00000000-0000-0000-0000-0000000009a1', 'Admin Sin Perfil', 'adm@example.test'),
  ('10000000-0000-0000-0000-0000000009b2', '00000000-0000-0000-0000-0000000009b2', 'Terapeuta Con Perfil', 'ter@example.test');
insert into public.person_roles (person_id, role_id) values
  ('10000000-0000-0000-0000-0000000009a1', (select id from public.roles where code = 'admin')),
  ('10000000-0000-0000-0000-0000000009b2', (select id from public.roles where code = 'therapist'));
insert into public.therapist_profiles (id, person_id, status_id) values
  ('20000000-0000-0000-0000-0000000009b2', '10000000-0000-0000-0000-0000000009b2', (select id from public.profile_statuses where code = 'unpublished'));

-- 1) anon cannot call it / anon no puede llamarla
set session authorization authenticator;
set role anon;
do $$
begin
  begin
    perform public.register_therapist('X', '{}'::jsonb);
    raise exception 'anon was allowed to call register_therapist';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 2) the admin without a profile completes the sign-up / el admin sin perfil completa el alta
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a1","role":"authenticated"}', true);
do $$
declare
  pid uuid;
  n_people int := (select count(*) from public.people where id in ('10000000-0000-0000-0000-0000000009a1','10000000-0000-0000-0000-0000000009b2'));
begin
  pid := public.register_therapist('Otro Nombre', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
  if pid is null then raise exception 'no profile id returned'; end if;
end
$$;
reset role;
reset session authorization;

do $$
begin
  if (select count(*) from public.therapist_profiles where person_id = '10000000-0000-0000-0000-0000000009a1') <> 1 then
    raise exception 'the admin must have exactly 1 profile';
  end if;
  if (select status_id from public.therapist_profiles where person_id = '10000000-0000-0000-0000-0000000009a1')
     <> (select id from public.profile_statuses where code = 'unpublished') then
    raise exception 'the new profile must be unpublished';
  end if;
  if (select full_name from public.people where id = '10000000-0000-0000-0000-0000000009a1') <> 'Admin Sin Perfil' then
    raise exception 'the existing name must be kept';
  end if;
  if (select count(*) from public.people where auth_user_id = '00000000-0000-0000-0000-0000000009a1') <> 1 then
    raise exception 'no second person may be created';
  end if;
  if not exists (select 1 from public.person_roles pr join public.roles r on r.id = pr.role_id
                 where pr.person_id = '10000000-0000-0000-0000-0000000009a1' and r.code = 'therapist') then
    raise exception 'the therapist role must be added';
  end if;
  if not exists (select 1 from public.person_roles pr join public.roles r on r.id = pr.role_id
                 where pr.person_id = '10000000-0000-0000-0000-0000000009a1' and r.code = 'admin') then
    raise exception 'the admin role must be kept';
  end if;
  if (select count(*) from public.terms_acceptances where person_id = '10000000-0000-0000-0000-0000000009a1' and revoked_at is null) <> 3 then
    raise exception 'expected 3 active acceptances';
  end if;
end
$$;

-- 3) a second call is refused (already registered), for both people / una segunda llamada se rechaza, para ambos
do $$
declare uid text;
begin
  foreach uid in array array['00000000-0000-0000-0000-0000000009a1', '00000000-0000-0000-0000-0000000009b2'] loop
    perform set_config('request.jwt.claims', '{"sub":"' || uid || '","role":"authenticated"}', true);
    set local session authorization authenticator;
    set local role authenticated;
    begin
      perform public.register_therapist('Nombre', '{"terms":"v1","privacy":"v1","legal_declaration":"v1"}'::jsonb);
      raise exception 'a second registration was accepted for %', uid;
    exception when unique_violation then null;
    end;
    reset role;
    reset session authorization;
  end loop;
end
$$;

-- nothing was duplicated / no se duplicó nada
do $$
begin
  if (select count(*) from public.therapist_profiles where person_id in
      ('10000000-0000-0000-0000-0000000009a1','10000000-0000-0000-0000-0000000009b2')) <> 2 then
    raise exception 'profiles were duplicated';
  end if;
end
$$;

rollback;
select 'OK 26-register-existing-person' as result;
