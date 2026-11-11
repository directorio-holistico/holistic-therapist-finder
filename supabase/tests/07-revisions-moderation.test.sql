-- Revisions, moderation events and restricted terms: isolation, column whitelist, flagging, no deletes.
-- Revisiones, eventos de moderación y términos restringidos: aislamiento, lista blanca de columnas, marcado, sin borrados.
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
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000c3'::uuid, id from public.roles where code = 'admin';
insert into public.therapist_profiles (id, person_id, status_id) values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1', (select id from public.profile_statuses where code = 'unpublished')),
  ('20000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-0000000000b2', (select id from public.profile_statuses where code = 'unpublished'));

-- 1) normalize_text and the starter list (as owner) / normalize_text y la lista inicial (como dueño)
do $$
begin
  if public.normalize_text('ÁÉÍÓÚ Ñandú CURACIÓN') <> 'aeiou nandu curacion' then
    raise exception 'normalize_text is wrong: %', public.normalize_text('ÁÉÍÓÚ Ñandú CURACIÓN');
  end if;
  if (select count(*) from public.restricted_terms where is_active) < 25 then raise exception 'starter list is missing'; end if;
  -- terms are stored normalized even if inserted with accents and capitals / los términos se guardan normalizados
  insert into public.restricted_terms (term) values ('  Sanación Garantizada ');
  if not exists (select 1 from public.restricted_terms where term = 'sanacion garantizada') then
    raise exception 'a term was not normalized on insert';
  end if;
end
$$;

-- 1b) Function permissions: authenticated yes; anon, service_role and PUBLIC no (the ACL itself, not only the inner check).
-- 1b) Permisos de funciones: authenticated sí; anon, service_role y PUBLIC no (la ACL en sí, no solo el chequeo interno).
do $$
declare
  f text;
begin
  foreach f in array array['public.find_restricted_terms(text)', 'public.normalize_text(text)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
    if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where p.oid = f::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
      raise exception 'PUBLIC can execute %', f;
    end if;
  end loop;
end
$$;

-- 2) Revisions constraints (as owner) / Restricciones de revisiones (como dueño)
do $$
declare
  ok boolean;
  a uuid := '20000000-0000-0000-0000-0000000000a1';
  rid uuid;
  st_pending smallint := (select id from public.revision_statuses where code = 'pending_review');
  st_rejected smallint := (select id from public.revision_statuses where code = 'rejected');
  st_approved smallint := (select id from public.revision_statuses where code = 'approved');
begin
  insert into public.profile_revisions (profile_id, payload) values (a, '{"headline":"Hola"}') returning id into rid;
  if (select status_id from public.profile_revisions where id = rid) <> (select id from public.revision_statuses where code = 'draft') then
    raise exception 'a new revision must start as draft';
  end if;
  -- one open revision per profile / una revisión abierta por perfil
  ok := false;
  begin insert into public.profile_revisions (profile_id, payload) values (a, '{}'); exception when unique_violation then ok := true; end;
  if not ok then raise exception 'two open revisions for one profile were accepted'; end if;
  -- payload must be an object / el payload debe ser un objeto
  ok := false;
  begin update public.profile_revisions set payload = '[1]' where id = rid; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a non-object payload was accepted'; end if;
  -- rejected without reason / rechazada sin motivo
  ok := false;
  begin update public.profile_revisions set status_id = st_rejected, closed_at = now() where id = rid; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a rejection without reason was accepted'; end if;
  -- closed status without closed_at, and open status with closed_at / estado final sin closed_at, y abierto con closed_at
  ok := false;
  begin update public.profile_revisions set status_id = st_approved where id = rid; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an approved revision without closed_at was accepted'; end if;
  ok := false;
  begin update public.profile_revisions set status_id = st_pending, closed_at = now() where id = rid; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a pending revision with closed_at was accepted'; end if;
  -- valid transitions / transiciones válidas
  update public.profile_revisions set status_id = st_pending, submitted_at = now(), due_at = now() + interval '7 days',
         flagged_terms = array['curacion'] where id = rid;
  update public.profile_revisions set status_id = st_rejected, rejection_reason = 'Promete curas', closed_at = now(), decided_at = now() where id = rid;
  -- after closing, a new open revision is allowed / cerrada, se permite una nueva abierta
  insert into public.profile_revisions (profile_id, payload) values (a, '{"headline":"Nueva"}');
  -- moderation event needs at least one status / el evento necesita al menos un estado
  ok := false;
  begin insert into public.moderation_events (profile_id, reason) values (a, 'x'); exception when check_violation then ok := true; end;
  if not ok then raise exception 'a moderation event without status was accepted'; end if;
  insert into public.moderation_events (profile_id, revision_id, actor_person_id, revision_status_id, reason)
    values (a, rid, '10000000-0000-0000-0000-0000000000c3', st_rejected, 'Promete curas');
end
$$;

-- B gets a draft too (still as owner) / B también tiene un borrador (aún como dueño)
insert into public.profile_revisions (profile_id, payload) values ('20000000-0000-0000-0000-0000000000b2', '{"headline":"De B"}');

-- 3) User A (therapist) / Usuario A (terapeuta)
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  stmt text;
  denied boolean;
  n integer;
  found_terms text[];
  own_open uuid;
begin
  -- visibility: only own revisions (2: one rejected with its reason, one draft); no moderation events, no terms
  if (select count(*) from public.profile_revisions) <> 2
     or exists (select 1 from public.profile_revisions where profile_id = '20000000-0000-0000-0000-0000000000b2') then
    raise exception 'A must see exactly their own 2 revisions';
  end if;
  if not exists (select 1 from public.profile_revisions where rejection_reason = 'Promete curas') then
    raise exception 'A must see the rejection reason of their own revision';
  end if;
  if (select count(*) from public.moderation_events) <> 0 then raise exception 'A can see moderation events'; end if;
  if (select count(*) from public.restricted_terms) <> 0 then raise exception 'A can read the restricted terms list'; end if;

  -- A edits own draft: payload and suggested_therapy only / A edita su borrador
  select id into own_open from public.profile_revisions where closed_at is null;
  update public.profile_revisions set payload = '{"headline":"Editado"}', suggested_therapy = 'Terapia nueva' where id = own_open;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'A could not edit their own draft'; end if;

  -- column whitelist: workflow fields and ownership cannot be touched
  foreach stmt in array array[
    $q$update public.profile_revisions set rejection_reason = 'x' where closed_at is null$q$,
    $q$update public.profile_revisions set due_at = now() where closed_at is null$q$,
    $q$update public.profile_revisions set flagged_terms = '{}' where closed_at is null$q$,
    $q$update public.profile_revisions set status_id = 3 where closed_at is null$q$,
    $q$update public.profile_revisions set profile_id = '20000000-0000-0000-0000-0000000000b2' where closed_at is null$q$,
    $q$update public.profile_revisions set is_priority = true where closed_at is null$q$,
    $q$delete from public.profile_revisions$q$,
    $q$insert into public.profile_revisions (profile_id, payload, status_id) values ('20000000-0000-0000-0000-0000000000a1', '{}', 3)$q$,
    $q$insert into public.moderation_events (profile_id, profile_status_id) values (null, 1)$q$,
    $q$insert into public.restricted_terms (term) values ('zzz')$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'A could run: %', stmt; end if;
  end loop;

  -- A cannot create a revision for B's profile (RLS) / A no crea una revisión para el perfil de B
  denied := false;
  begin insert into public.profile_revisions (profile_id, payload) values ('20000000-0000-0000-0000-0000000000b2', '{}');
  exception when insufficient_privilege or unique_violation then denied := true; end;
  if not denied then raise exception 'A created a revision for B'; end if;

  -- restricted terms never block: A can check a text and gets the flagged terms
  found_terms := public.find_restricted_terms('Ofrezco CURACIÓN de cáncer, sin milagros ni procura');
  if found_terms <> array['cancer', 'curacion', 'milagros'] then
    raise exception 'find_restricted_terms returned %', found_terms;
  end if;
  if public.find_restricted_terms('Acompaño procesos de calma y meditación') <> '{}' then raise exception 'false positive on a clean text'; end if;
  if public.find_restricted_terms('Es 100% efectivo, garantizado.') <> array['100% efectivo', 'garantizado'] then
    raise exception 'phrases with symbols are not matched';
  end if;
  if public.find_restricted_terms(null) <> '{}' then raise exception 'null text must return an empty list'; end if;
  denied := false;
  begin perform public.find_restricted_terms(repeat('a', 5001)); exception when sqlstate '22023' then denied := true; end;
  if not denied then raise exception 'a 5001-character text was accepted'; end if;
end
$$;
reset role;
reset session authorization;

-- 4) Once submitted, the therapist cannot edit it (owner marks A's draft as pending) / Una vez enviada, no se edita
update public.profile_revisions set status_id = (select id from public.revision_statuses where code = 'pending_review'),
       submitted_at = now(), due_at = now() + interval '7 days' where profile_id = '20000000-0000-0000-0000-0000000000a1' and closed_at is null;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare n integer;
begin
  update public.profile_revisions set payload = '{"headline":"Tarde"}' where closed_at is null;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'A edited a revision that is already pending review'; end if;
end
$$;
reset role;
reset session authorization;

-- 5) User B sees only theirs; admin C sees everything and manages terms; D and anon see nothing.
-- 5) B ve solo lo suyo; el admin C ve todo y gestiona términos; D y anon no ven nada.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.profile_revisions) <> 1
     or (select profile_id from public.profile_revisions) <> '20000000-0000-0000-0000-0000000000b2' then
    raise exception 'B must see only their own revision';
  end if;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare
  n integer;
  denied boolean;
  stmt text;
begin
  if (select count(*) from public.profile_revisions) <> 3 then raise exception 'admin must see all 3 revisions'; end if;
  if (select count(*) from public.moderation_events) <> 1 then raise exception 'admin must see the moderation event'; end if;
  -- admin manages the terms list (the four policies) / el admin gestiona la lista de términos
  insert into public.restricted_terms (term, note) values ('Sanador Milagroso', 'test');
  update public.restricted_terms set is_active = false where term = 'sanador milagroso';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'admin could not update a term'; end if;
  delete from public.restricted_terms where term = 'sanador milagroso';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'admin could not delete a term'; end if;
  -- an inactive term no longer flags / un término inactivo ya no marca
  update public.restricted_terms set is_active = false where term = 'milagro';
  if 'milagro' = any (public.find_restricted_terms('un milagro')) then raise exception 'an inactive term still flags'; end if;
  -- editing someone else's revision is filtered by RLS (0 rows, no error) / editar la revisión de otro lo filtra la RLS (0 filas)
  update public.profile_revisions set payload = '{"headline":"Admin"}';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'admin edited a revision through the API'; end if;
  -- the admin does NOT write revisions or events through the API / el admin no escribe revisiones ni eventos por la API
  foreach stmt in array array[
    $q$delete from public.profile_revisions$q$,
    $q$insert into public.moderation_events (profile_status_id) values (1)$q$,
    $q$delete from public.moderation_events$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'admin could run: %', stmt; end if;
  end loop;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.profile_revisions) <> 0 or (select count(*) from public.moderation_events) <> 0
     or (select count(*) from public.restricted_terms) <> 0 then
    raise exception 'a login without a person record must see nothing';
  end if;
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
    'select 1 from public.profile_revisions',
    'select 1 from public.moderation_events',
    'select 1 from public.restricted_terms',
    $q$select public.find_restricted_terms('curacion')$q$,
    $q$select public.normalize_text('A')$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: revisions, moderation and restricted terms behave as designed / revisiones, moderacion y terminos segun el diseno'
