-- Submitting and discarding revisions: deadlines in business days, flagging, ownership, states, permissions.
-- Enviar y descartar revisiones: plazos en días hábiles, marcado, pertenencia, estados, permisos.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'c@example.test');
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Persona A', 'a@example.test'),
  ('10000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2', 'Persona B', 'b@example.test'),
  ('10000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c3', 'Persona C', 'c@example.test');
-- A never approved (first submission); B already approved once (a change); C suspended.
-- A nunca aprobado (alta); B ya aprobado una vez (cambio); C suspendido.
insert into public.therapist_profiles (id, person_id, status_id, approved_at) values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1', (select id from public.profile_statuses where code = 'unpublished'), null),
  ('20000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-0000000000b2', (select id from public.profile_statuses where code = 'unpublished'), now()),
  ('20000000-0000-0000-0000-0000000000c3', '10000000-0000-0000-0000-0000000000c3', (select id from public.profile_statuses where code = 'suspended'), now());

-- 1) add_business_days (as owner) / add_business_days (como dueño)
do $$
begin
  -- Wed 11/11/2026 10:00 (Argentina) + 7 business days = Fri 20/11/2026 10:00
  if public.add_business_days('2026-11-11 10:00:00-03', 7) <> '2026-11-20 10:00:00-03'::timestamptz then
    raise exception '7 business days from Wednesday are wrong: %', public.add_business_days('2026-11-11 10:00:00-03', 7);
  end if;
  -- Fri + 1 = Mon / viernes + 1 = lunes
  if public.add_business_days('2026-11-13 10:00:00-03', 1) <> '2026-11-16 10:00:00-03'::timestamptz then
    raise exception 'Friday + 1 must be Monday';
  end if;
  -- Sat + 1 = Mon / sábado + 1 = lunes
  if public.add_business_days('2026-11-14 10:00:00-03', 1) <> '2026-11-16 10:00:00-03'::timestamptz then
    raise exception 'Saturday + 1 must be Monday';
  end if;
  -- 0 days keeps the moment / 0 días conserva el momento
  if public.add_business_days('2026-11-11 10:00:00-03', 0) <> '2026-11-11 10:00:00-03'::timestamptz then
    raise exception '0 days must not move';
  end if;
  begin perform public.add_business_days(now(), 61); raise exception 'accepted 61 days';
  exception when sqlstate '22023' then null; end;
end
$$;

-- 2) Settings validation (owner) / Validación de ajustes (dueño)
do $$
declare ok boolean;
begin
  ok := false;
  begin update public.app_settings set value = '0' where key = 'review_days_initial'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'review_days_initial = 0 was accepted'; end if;
  ok := false;
  begin update public.app_settings set value = '31' where key = 'review_days_update'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'review_days_update = 31 was accepted'; end if;
  ok := false;
  begin update public.app_settings set value = '"x"' where key = 'review_days_priority'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a text review_days_priority was accepted'; end if;
  if (select count(*) from public.app_settings where key like 'review\_days\_%' and is_public) <> 3 then
    raise exception 'the 3 review settings must exist and be public';
  end if;
end
$$;

-- Drafts created by the owner (the therapist does the same through the API, tested elsewhere)
insert into public.profile_revisions (id, profile_id, payload, suggested_therapy) values
  ('30000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-0000000000a1',
   '{"headline":"Ofrezco CURACIÓN real","therapies":[{"note":"sin milagros","minutes":60}],"practice_start_year":2015}', 'Terapia de prueba'),
  ('30000000-0000-0000-0000-0000000000b2', '20000000-0000-0000-0000-0000000000b2', '{"headline":"Acompaño procesos de calma"}', null),
  ('30000000-0000-0000-0000-0000000000c3', '20000000-0000-0000-0000-0000000000c3', '{"headline":"Hola"}', null);

-- 3) User A / Usuario A
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  flagged text[];
  r public.profile_revisions%rowtype;
  ok boolean;
begin
  -- other people's revisions are not found, and the answer does not reveal whether they exist
  ok := false;
  begin perform public.submit_revision('30000000-0000-0000-0000-0000000000b2'); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'A could submit the revision of B'; end if;
  ok := false;
  begin perform public.discard_revision('30000000-0000-0000-0000-0000000000b2'); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'A could discard the revision of B'; end if;
  ok := false;
  begin perform public.submit_revision(gen_random_uuid()); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'a random id must give the same answer as a foreign revision'; end if;

  -- submit: flags are returned and stored; sending is never blocked
  flagged := public.submit_revision('30000000-0000-0000-0000-0000000000a1');
  if flagged <> array['curacion', 'milagros'] then raise exception 'wrong flagged terms: %', flagged; end if;
  select * into r from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a1';
  if r.flagged_terms <> flagged then raise exception 'flagged terms were not stored'; end if;
  if r.status_id <> (select id from public.revision_statuses where code = 'pending_review') then raise exception 'not pending after submit'; end if;
  if r.submitted_at is null or r.due_at is null then raise exception 'submitted_at and due_at must be set'; end if;

  -- cannot submit twice / no se envía dos veces
  ok := false;
  begin perform public.submit_revision('30000000-0000-0000-0000-0000000000a1'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a pending revision was submitted again'; end if;

  -- discard the pending one, then a new draft can be created through the API
  perform public.discard_revision('30000000-0000-0000-0000-0000000000a1');
  if (select closed_at from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a1') is null then
    raise exception 'discard did not close the revision';
  end if;
  ok := false;
  begin perform public.discard_revision('30000000-0000-0000-0000-0000000000a1'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a discarded revision was discarded again'; end if;
  insert into public.profile_revisions (profile_id, payload) values ('20000000-0000-0000-0000-0000000000a1', '{}');
  -- empty and unknown payloads are refused at submission
  ok := false;
  begin perform public.submit_revision((select id from public.profile_revisions where closed_at is null)); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an empty revision was submitted'; end if;
  update public.profile_revisions set payload = '{"is_admin":true}' where closed_at is null;
  ok := false;
  begin perform public.submit_revision((select id from public.profile_revisions where closed_at is null)); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'unknown payload keys were accepted'; end if;
  update public.profile_revisions set payload = '{"headline":"Un texto limpio"}' where closed_at is null;
end
$$;
reset role;
reset session authorization;

-- Deadlines: A's first submission = 7 business days; high priority = 1 (owner marks the new draft as priority)
do $$
declare
  rid uuid := (select id from public.profile_revisions where profile_id = '20000000-0000-0000-0000-0000000000a1' and closed_at is null);
begin
  -- Wait: the previous submission (7 days) was already discarded; re-check its stored due date first
  if (select due_at from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a1')
     <> public.add_business_days((select submitted_at from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a1'), 7) then
    raise exception 'a first submission must be due in 7 business days';
  end if;
  update public.profile_revisions set is_priority = true where id = rid;
end
$$;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.submit_revision((select id from public.profile_revisions where profile_id = '20000000-0000-0000-0000-0000000000a1' and closed_at is null));
reset role;
reset session authorization;
do $$
declare r public.profile_revisions%rowtype;
begin
  select * into r from public.profile_revisions where profile_id = '20000000-0000-0000-0000-0000000000a1' and closed_at is null;
  if r.due_at <> public.add_business_days(r.submitted_at, 1) then raise exception 'priority must be due in 1 business day'; end if;
  if r.flagged_terms <> '{}' then raise exception 'a clean text must not be flagged'; end if;
end
$$;

-- 4) User B: a change on an approved profile = 3 business days; the configured value is respected
update public.app_settings set value = '5' where key = 'review_days_update';
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select public.submit_revision('30000000-0000-0000-0000-0000000000b2');
reset role;
reset session authorization;
do $$
declare r public.profile_revisions%rowtype;
begin
  select * into r from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000b2';
  if r.due_at <> public.add_business_days(r.submitted_at, 5) then raise exception 'the configured 5 days were not used'; end if;
end
$$;

-- 5) User C (suspended profile) cannot submit; D (no person) and anon are refused
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.submit_revision('30000000-0000-0000-0000-0000000000c3'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a suspended profile submitted a revision'; end if;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.submit_revision('30000000-0000-0000-0000-0000000000a1'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a login without a person record could submit'; end if;
  ok := false;
  begin perform public.discard_revision('30000000-0000-0000-0000-0000000000a1'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a login without a person record could discard'; end if;
end
$$;
reset role;
reset session authorization;

set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare
  stmt text;
  denied boolean;
begin
  foreach stmt in array array[
    $q$select public.submit_revision(gen_random_uuid())$q$,
    $q$select public.discard_revision(gen_random_uuid())$q$,
    $q$select public.add_business_days(now(), 1)$q$,
    $q$select public.match_restricted_terms('curacion')$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 6) Function permissions and the fixed search_path of EVERY security definer function (guard for future ones)
-- 6) Permisos de funciones y search_path fijo de TODA función security definer (guarda también para las futuras)
do $$
declare
  f text;
  r record;
begin
  foreach f in array array['public.submit_revision(uuid)', 'public.discard_revision(uuid)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
  end loop;
  foreach f in array array['public.add_business_days(timestamptz,integer)', 'public.match_restricted_terms(text)'] loop
    if has_function_privilege('authenticated', f, 'EXECUTE') or has_function_privilege('anon', f, 'EXECUTE')
       or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'an API role can execute the internal function %', f;
    end if;
  end loop;
  -- no function in public may be executable by PUBLIC
  for r in
    select p.oid::regprocedure::text as sig from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE')
  loop
    raise exception 'PUBLIC can execute %', r.sig;
  end loop;
  -- every security definer function has a fixed search_path
  for r in
    select p.oid::regprocedure::text as sig from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    raise exception 'security definer function without fixed search_path: %', r.sig;
  end loop;
end
$$;

rollback;
\echo 'OK: revision submission works, flags never block, permissions are closed / envio de revisiones correcto, el marcado no bloquea, permisos cerrados'
