-- Re-acceptance gate: pending documents, blocked writes, never-blocked rights, accepting, administrators, permissions.
-- Puerta de re-aceptación: documentos pendientes, escrituras bloqueadas, derechos que nunca se bloquean, aceptar, administradores, permisos.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- Helpers: run a statement as the CURRENT role and compare the SQLSTATE it ends with.
-- Ayudas: ejecutan una sentencia con el rol ACTUAL y comparan el SQLSTATE con el que termina.
create function pg_temp.expect_state(p_state text, p_stmt text, p_label text) returns void language plpgsql as $$
declare got text;
begin
  begin execute p_stmt; got := 'no error';
  exception when others then got := sqlstate; end;
  if got is distinct from p_state then raise exception '%: expected %, got %', p_label, p_state, got; end if;
end $$;
-- passes the gate: ANY outcome except AC001 (the rest of the function may fail for other reasons)
-- pasa la puerta: CUALQUIER resultado menos AC001 (el resto de la función puede fallar por otros motivos)
create function pg_temp.expect_not_gated(p_stmt text, p_label text) returns void language plpgsql as $$
declare got text;
begin
  begin execute p_stmt; got := 'no error';
  exception when others then got := sqlstate; end;
  if got = 'AC001' then raise exception '%: the gate blocked it', p_label; end if;
end $$;

-- The baseline migration removes EXECUTE from PUBLIC on new functions, so the helpers are opened to the roles that call them.
-- La migración base quita EXECUTE a PUBLIC en funciones nuevas, así que las ayudas se abren a los roles que las llaman.
grant execute on function pg_temp.expect_state(text, text, text), pg_temp.expect_not_gated(text, text) to anon, authenticated;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test', now()),   -- therapist A
  ('00000000-0000-0000-0000-0000000000e5', 'e@example.test', now());   -- admin
insert into public.people (id, auth_user_id, full_name, email)
  values ('10000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000e5', 'Admin E', 'e@example.test');
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000e5'::uuid, id from public.roles where code = 'admin';

-- 1) Constraints of the new column (as owner) / Restricciones de la columna nueva (dueño)
do $$
begin
  if exists (select 1 from public.legal_document_types where minimum_version is not null) then
    raise exception 'the gate must start OFF: every minimum_version must be null';
  end if;
  perform pg_temp.expect_state('23514', $q$update public.legal_document_types set minimum_version = 'v1' where code = 'offers_consent'$q$, 'minimum on an optional document');
  perform pg_temp.expect_state('23514', $q$update public.legal_document_types set minimum_version = 'bad version!' where code = 'terms'$q$, 'invalid minimum format');
end
$$;

-- 2) A registers (versions 2026-11) and, with the gate OFF, can write / A se registra y, con la puerta APAGADA, escribe
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.register_therapist('Ana', '{"terms":"2026-11","privacy":"2026-11","legal_declaration":"2026-11"}');
do $$
declare pid uuid := (select id from public.therapist_profiles where person_id = public.current_person_id());
begin
  if pid is null then raise exception 'A has no profile'; end if;
  if public.my_pending_documents() <> '{}' then raise exception 'with the gate OFF nothing can be pending'; end if;
  insert into public.profile_revisions (profile_id, payload) values (pid, '{"headline":"hola"}');
  perform public.set_photo_consent(true, 'v1');
end
$$;
reset role;
reset session authorization;

-- 3) Turn the gate ON: the minimum is newer than what A accepted / Encender la puerta: el mínimo es más nuevo que lo aceptado
update public.legal_document_types set minimum_version = '2026-12' where code in ('terms', 'privacy', 'legal_declaration');

set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  pid uuid := (select id from public.therapist_profiles where person_id = public.current_person_id());
  rid uuid := (select id from public.profile_revisions where profile_id = (select id from public.therapist_profiles where person_id = public.current_person_id()) and closed_at is null);
  me  uuid := public.current_person_id();
begin
  if (select array_agg(c order by c) from unnest(public.my_pending_documents()) c) <> array['legal_declaration', 'privacy', 'terms'] then
    raise exception 'the 3 required documents must be pending, got %', public.my_pending_documents();
  end if;
  -- every way of changing something is blocked / todas las formas de cambiar algo están bloqueadas
  perform pg_temp.expect_state('AC001', format($q$insert into public.profile_revisions (profile_id, payload) values (%L, '{}')$q$, pid), 'insert revision');
  perform pg_temp.expect_state('AC001', format($q$update public.profile_revisions set payload = '{"headline":"x"}' where id = %L$q$, rid), 'update revision');
  perform pg_temp.expect_state('AC001', format($q$insert into public.location_requests (profile_id, region_id, city_name) values (%L, 1, 'x')$q$, pid), 'insert location request');
  perform pg_temp.expect_state('AC001', format($q$select public.submit_revision(%L)$q$, rid), 'submit_revision');
  perform pg_temp.expect_state('AC001', $q$select public.update_my_rates('[]'::jsonb)$q$, 'update_my_rates');
  perform pg_temp.expect_state('AC001', $q$select public.confirm_my_rates()$q$, 'confirm_my_rates');
  perform pg_temp.expect_state('AC001', $q$select public.set_photo_consent(true, 'v1')$q$, 'give the photo consent');
  -- rights that are NEVER blocked / derechos que NUNCA se bloquean
  perform public.set_photo_consent(false);                 -- withdraw the photo consent
  perform public.discard_revision(rid);                    -- discard an own revision
  if (select count(*) from public.terms_acceptances where person_id = me) < 3 then raise exception 'A must still read the own acceptances'; end if;
end
$$;

-- 4) accept_current_documents: strict validation / validación estricta
do $$
begin
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents(null)$q$, 'null');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('[]')$q$, 'not an object');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{}')$q$, 'empty');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"2026-12","privacy":"2026-12"}')$q$, 'missing a pending document');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"2026-12","privacy":"2026-12","legal_declaration":"2026-12","offers_consent":"2026-12"}')$q$, 'an extra document');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"2026-11","privacy":"2026-12","legal_declaration":"2026-12"}')$q$, 'a version older than the minimum');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"bad version!","privacy":"2026-12","legal_declaration":"2026-12"}')$q$, 'invalid version');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":5,"privacy":"2026-12","legal_declaration":"2026-12"}')$q$, 'a non-text version');
  if public.my_pending_documents() = '{}' then raise exception 'a failed call accepted something'; end if;

  perform public.accept_current_documents('{"terms":"2026-12","privacy":"2026-12","legal_declaration":"2026-12"}');
  if public.my_pending_documents() <> '{}' then raise exception 'nothing should be pending after accepting'; end if;
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"2026-12","privacy":"2026-12","legal_declaration":"2026-12"}')$q$, 'accepting twice');
  -- the old acceptances stay as history: 3 old + 3 new / las anteriores quedan como historia
  if (select count(*) from public.terms_acceptances ta join public.legal_document_types d on d.id = ta.document_type_id
       where ta.person_id = public.current_person_id() and d.is_required and ta.revoked_at is null) <> 6 then
    raise exception 'expected 6 active required acceptances (3 old + 3 new)';
  end if;
end
$$;

-- 5) After accepting, the gate lets A through (other errors are fine here) / Tras aceptar, la puerta deja pasar
do $$
declare pid uuid := (select id from public.therapist_profiles where person_id = public.current_person_id());
begin
  insert into public.profile_revisions (profile_id, payload) values (pid, '{"headline":"chau"}');
  perform pg_temp.expect_not_gated($q$select public.update_my_rates('[]'::jsonb)$q$, 'update_my_rates after accepting');
  perform pg_temp.expect_not_gated($q$select public.confirm_my_rates()$q$, 'confirm_my_rates after accepting');
  perform pg_temp.expect_not_gated($q$select public.set_photo_consent(true, 'v1')$q$, 'photo consent after accepting');
  perform pg_temp.expect_not_gated(format($q$select public.submit_revision(%L)$q$, (select id from public.profile_revisions where profile_id = pid and closed_at is null)), 'submit_revision after accepting');
end
$$;
reset role;
reset session authorization;

-- 6) A SUBSTANTIAL change: the minimum goes up and A must accept again / Un cambio SUSTANCIAL: sube el mínimo y A debe aceptar de nuevo
update public.legal_document_types set minimum_version = '2026-12-b' where code = 'terms';
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
begin
  if public.my_pending_documents() <> array['terms'] then raise exception 'only the terms must be pending, got %', public.my_pending_documents(); end if;
  perform pg_temp.expect_state('AC001', $q$select public.confirm_my_rates()$q$, 'blocked again');
  perform pg_temp.expect_state('22023', $q$select public.accept_current_documents('{"terms":"2026-12","privacy":"2026-12"}')$q$, 'only the pending ones are accepted');
  perform public.accept_current_documents('{"terms":"2026-12-b"}');
  if public.my_pending_documents() <> '{}' then raise exception 'the terms must be accepted now'; end if;
end
$$;
reset role;
reset session authorization;

-- 7) Administrators are never blocked, and a login without a person gets no answer / Los admin nunca quedan bloqueados
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
do $$
begin
  if public.my_pending_documents() = '{}' then raise exception 'the admin has no acceptances: the helper must report them pending'; end if;
  -- an administrator writing a revision directly must not meet the gate (RLS may still refuse; that is another error)
  perform pg_temp.expect_not_gated($q$update public.profile_revisions set payload = payload$q$, 'admin update');
end
$$;
reset role;
reset session authorization;

-- 8) anon: nothing / anon: nada
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  perform pg_temp.expect_state('42501', $q$select public.my_pending_documents()$q$, 'anon my_pending_documents');
  perform pg_temp.expect_state('42501', $q$select public.accept_current_documents('{}')$q$, 'anon accept_current_documents');
  perform pg_temp.expect_state('42501', $q$select public.assert_current_acceptances()$q$, 'anon assert_current_acceptances');
end
$$;
reset role;
reset session authorization;

-- 9) Permissions / Permisos
do $$
declare f text;
begin
  foreach f in array array['public.my_pending_documents()', 'public.accept_current_documents(jsonb)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
  end loop;
  foreach f in array array['public.assert_current_acceptances()', 'public.require_current_acceptances()'] loop
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('authenticated', f, 'EXECUTE')
       or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'an API role can execute %', f;
    end if;
  end loop;
  -- the four replaced functions keep their permissions / las cuatro funciones reemplazadas conservan sus permisos
  foreach f in array array['public.submit_revision(uuid)', 'public.update_my_rates(jsonb)', 'public.confirm_my_rates()', 'public.set_photo_consent(boolean,text)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated lost EXECUTE on %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role gained EXECUTE on %', f;
    end if;
  end loop;
  if (select count(*) from pg_trigger t where not t.tgisinternal
        and t.tgname in ('acceptance_gate_profile_revisions', 'acceptance_gate_location_requests')) <> 2 then
    raise exception 'expected the 2 gate triggers';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')) then
    raise exception 'PUBLIC can execute a function in public';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
               and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')) then
    raise exception 'a security definer function has no fixed search_path';
  end if;
end
$$;

rollback;
\echo 'OK: the re-acceptance gate blocks changes, never blocks the rights of the person, and exempts administrators / la puerta de re-aceptación bloquea cambios, nunca bloquea los derechos de la persona y exime a los administradores'
