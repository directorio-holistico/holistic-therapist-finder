-- Approving and rejecting revisions: the only way a live profile changes. Atomicity, validation, roles, audit.
-- Aprobar y rechazar revisiones: la única forma de cambiar un perfil vigente. Atomicidad, validación, roles, auditoría.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test'),  -- therapist, first submission
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test'),  -- therapist, published
  ('00000000-0000-0000-0000-0000000000c3', 'c@example.test'),  -- therapist, suspended
  ('00000000-0000-0000-0000-0000000000d4', 'd@example.test'),  -- admin
  ('00000000-0000-0000-0000-0000000000e5', 'e@example.test'),  -- admin with own profile
  ('00000000-0000-0000-0000-0000000000f6', 'f@example.test');  -- therapist, paused
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000000' || right(u.id::text, 2))::uuid, u.id, 'Persona ' || right(u.id::text, 2), u.email
  from auth.users u;
insert into public.person_roles (person_id, role_id)
  select ('10000000-0000-0000-0000-0000000000' || x)::uuid, (select id from public.roles where code = 'admin') from unnest(array['d4', 'e5']) x;

-- Profiles (owner, as the server does) / Perfiles (dueño, como hace el servidor)
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, headline)
  select ('20000000-0000-0000-0000-0000000000' || x.k)::uuid, ('10000000-0000-0000-0000-0000000000' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'),
         case when x.k = 'a1' then null else now() - interval '30 days' end,
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
         'Original ' || x.k
  from (values ('a1'), ('b2'), ('c3'), ('e5'), ('f6')) x(k);
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000000' || x)::uuid, (select id from public.contact_types where code = 'phone'), '+54 351 555 0102'
  from unnest(array['b2', 'c3', 'e5', 'f6']) x;
insert into public.profile_contacts (profile_id, contact_type_id, value)
  values ('20000000-0000-0000-0000-0000000000b2', (select id from public.contact_types where code = 'email'), 'b@example.test');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000000b2', '20000000-0000-0000-0000-0000000000e5');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'suspended') where id = '20000000-0000-0000-0000-0000000000c3';
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused') where id = '20000000-0000-0000-0000-0000000000f6';

-- helper to open a pending revision (owner) / ayuda para abrir una revisión pendiente (dueño)
create function pg_temp.open_revision(p_id uuid, p_profile text, p_payload jsonb, p_status text default 'pending_review')
returns void language sql as $$
  insert into public.profile_revisions (id, profile_id, status_id, payload, submitted_at, due_at)
  values (p_id, ('20000000-0000-0000-0000-0000000000' || p_profile)::uuid,
          (select id from public.revision_statuses where code = p_status), p_payload, now(), now() + interval '3 days');
$$;
-- 1) FIRST APPROVAL: everything is applied, the profile is published / PRIMERA APROBACIÓN
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a1', 'a1', (
  select jsonb_build_object(
    'headline', 'Acompaño procesos de calma', 'zone', 'Centro', 'practice_start_year', 2015,
    'location_id', (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
    'languages', (select jsonb_agg(id) from public.languages where code in ('es', 'en')),
    'service_modes', (select jsonb_agg(id) from public.service_modes),
    'session_formats', (select jsonb_agg(id) from public.session_formats where code = 'individual'),
    'therapies', jsonb_build_array(
      jsonb_build_object('therapy_id', (select id from public.therapies where is_active order by id limit 1), 'session_minutes', 60,
        'rates', jsonb_build_array(
          jsonb_build_object('rate_audience_id', (select id from public.rate_audiences where code = 'own_country'), 'amount', 15000, 'currency_id', (select id from public.currencies where code = 'ARS')),
          jsonb_build_object('rate_audience_id', (select id from public.rate_audiences where code = 'other_countries'), 'amount', 30, 'currency_id', (select id from public.currencies where code = 'USD')))),
      jsonb_build_object('therapy_id', (select id from public.therapies where is_active order by id limit 1 offset 1))),
    'contacts', jsonb_build_array(
      jsonb_build_object('contact_type_id', (select id from public.contact_types where code = 'phone'), 'value', '+54 299 555 0111', 'accepts_whatsapp', true),
      jsonb_build_object('contact_type_id', (select id from public.contact_types where code = 'email'), 'value', 'a@example.test'),
      jsonb_build_object('contact_type_id', (select id from public.contact_types where code = 'website'), 'value', 'https://example.test/a')))));

set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000000a1');
reset role;
reset session authorization;

do $$
declare p public.therapist_profiles%rowtype; r public.profile_revisions%rowtype;
begin
  select * into p from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1';
  if p.status_id <> (select id from public.profile_statuses where code = 'published') then raise exception 'first approval must publish'; end if;
  if p.approved_at is null or p.headline <> 'Acompaño procesos de calma' or p.zone <> 'Centro' or p.practice_start_year <> 2015 then
    raise exception 'scalar fields were not applied';
  end if;
  if (select count(*) from public.profile_languages where profile_id = p.id) <> 2
     or (select count(*) from public.profile_service_modes where profile_id = p.id) <> 2
     or (select count(*) from public.profile_session_formats where profile_id = p.id) <> 1
     or (select count(*) from public.profile_therapies where profile_id = p.id) <> 2
     or (select count(*) from public.profile_therapy_rates where profile_id = p.id) <> 2
     or (select count(*) from public.profile_contacts where profile_id = p.id) <> 3 then
    raise exception 'lists were not applied';
  end if;
  if not (select accepts_whatsapp from public.profile_contacts where profile_id = p.id and contact_type_id = (select id from public.contact_types where code = 'phone')) then
    raise exception 'whatsapp flag lost';
  end if;
  select * into r from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a1';
  if r.status_id <> (select id from public.revision_statuses where code = 'approved') or r.closed_at is null or r.decided_at is null then
    raise exception 'revision not closed as approved';
  end if;
  if (select count(*) from public.moderation_events
       where revision_id = r.id and actor_person_id = '10000000-0000-0000-0000-0000000000d4'
         and revision_status_id = r.status_id and profile_status_id = p.status_id) <> 1 then
    raise exception 'the moderation event is missing or wrong';
  end if;
end
$$;

-- 2) CHANGE on a published profile: approved_at stays, status stays, removed contact is gone / CAMBIO en perfil publicado
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000b2', 'b2', jsonb_build_object(
  'headline', 'Titular nuevo',
  'contacts', jsonb_build_array(jsonb_build_object('contact_type_id', (select id from public.contact_types where code = 'phone'), 'value', '+54 299 555 0222'))));
do $$ begin perform set_config('test.b_approved', (select approved_at::text from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2'), true); end $$;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000000b2');
reset role;
reset session authorization;
do $$
declare p public.therapist_profiles%rowtype;
begin
  select * into p from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2';
  if p.headline <> 'Titular nuevo' then raise exception 'change not applied'; end if;
  if p.approved_at::text <> current_setting('test.b_approved') then raise exception 'approved_at must not change on later approvals'; end if;
  if (select count(*) from public.profile_contacts where profile_id = p.id) <> 1 then raise exception 'the omitted email must be removed'; end if;
  if (select value from public.profile_contacts where profile_id = p.id) <> '+54 299 555 0222' then raise exception 'phone not updated'; end if;
  if (select profile_status_id from public.moderation_events where revision_id = '30000000-0000-0000-0000-0000000000b2') is not null then
    raise exception 'no status change must be recorded when the status did not change';
  end if;
end
$$;

-- 3) INVALID payloads: nothing is applied and the revision stays pending (all-or-nothing)
-- 3) Contenidos INVÁLIDOS: no se aplica nada y la revisión sigue pendiente (todo o nada)
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000b3', 'b2', '{"headline":"No debe aplicarse"}');
create function pg_temp.try_bad(p_label text, p_payload jsonb, p_expected text) returns void
language plpgsql as $$
declare accepted boolean := false; state text;
begin
  update public.profile_revisions set payload = p_payload where id = '30000000-0000-0000-0000-0000000000b3';
  begin
    set local role authenticated;
    perform public.approve_revision('30000000-0000-0000-0000-0000000000b3');
    accepted := true;
  exception when others then
    state := sqlstate;
    if state <> p_expected then raise exception 'case [%]: expected %, got % (%)', p_label, p_expected, state, sqlerrm; end if;
  end;
  reset role;
  if accepted then raise exception 'case [%] was accepted', p_label; end if;
  if (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2') <> 'Titular nuevo' then
    raise exception 'case [%] left a partial change', p_label;
  end if;
  if (select closed_at from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000b3') is not null then
    raise exception 'case [%] closed the revision', p_label;
  end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
declare
  hidden  int := (select id from public.therapies where not is_active order by id limit 1);
  country int := (select id from public.locations where iso_code = 'AR');
  t1 int := (select id from public.therapies where is_active order by id limit 1);
  t2 int := (select id from public.therapies where is_active order by id limit 1 offset 1);
  own int := (select id from public.rate_audiences where code = 'own_country');
  ars int := (select id from public.currencies where code = 'ARS');
  usd int := (select id from public.currencies where code = 'USD');
  phone int := (select id from public.contact_types where code = 'phone');
begin
  if hidden is null then raise exception 'fixture: expected a hidden therapy'; end if;
  perform pg_temp.try_bad('headline as number', '{"headline":5}', '22023');
  perform pg_temp.try_bad('unknown key', '{"is_admin":true}', '22023');
  perform pg_temp.try_bad('hidden therapy', jsonb_build_object('headline', 'X', 'therapies', jsonb_build_array(jsonb_build_object('therapy_id', hidden))), '22023');
  perform pg_temp.try_bad('therapies not a list', '{"therapies":"x"}', '22023');
  perform pg_temp.try_bad('unknown language', '{"languages":[99999]}', '22023');
  perform pg_temp.try_bad('language as text', '{"languages":["es"]}', '22023');
  perform pg_temp.try_bad('photo path traversal', '{"photo_path":"../x.png"}', '22023');
  perform pg_temp.try_bad('photo of another profile', '{"photo_path":"20000000-0000-0000-0000-0000000000a1/x.png"}', '22023');
  perform pg_temp.try_bad('country as base location', jsonb_build_object('location_id', country), '23514');
  perform pg_temp.try_bad('unknown location', '{"location_id":99999999}', '22023');
  perform pg_temp.try_bad('rate amount as text', jsonb_build_object('therapies', jsonb_build_array(jsonb_build_object('therapy_id', t1,
    'rates', jsonb_build_array(jsonb_build_object('rate_audience_id', own, 'amount', 'x', 'currency_id', ars))))), '22023');
  perform pg_temp.try_bad('unknown contact type', '{"contacts":[{"contact_type_id":99,"value":"x"}]}', '22023');
  perform pg_temp.try_bad('published profile without phone', '{"contacts":[]}', '23514');
  perform pg_temp.try_bad('invalid phone', jsonb_build_object('contacts', jsonb_build_array(jsonb_build_object('contact_type_id', phone, 'value', 'abc'))), '23514');
  perform pg_temp.try_bad('more therapies than allowed', jsonb_build_object('therapies',
    (select jsonb_agg(jsonb_build_object('therapy_id', id)) from (select id from public.therapies where is_active order by id limit 5) t)), '23514');
  perform pg_temp.try_bad('two currencies for one audience', jsonb_build_object('therapies', jsonb_build_array(
    jsonb_build_object('therapy_id', t1, 'rates', jsonb_build_array(jsonb_build_object('rate_audience_id', own, 'amount', 1, 'currency_id', ars))),
    jsonb_build_object('therapy_id', t2, 'rates', jsonb_build_array(jsonb_build_object('rate_audience_id', own, 'amount', 1, 'currency_id', usd))))), '23514');
end
$$;
-- the pending revision of B is no longer needed / la revisión pendiente de B ya no hace falta
update public.profile_revisions set status_id = (select id from public.revision_statuses where code = 'discarded'),
  closed_at = now() where id = '30000000-0000-0000-0000-0000000000b3';

-- 4) REJECTION: reason required, profile untouched, the therapist can read the reason, events recorded
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000b4', 'b2', '{"headline":"Ofrezco curación de cáncer"}');
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
declare ok boolean;
begin
  begin perform public.reject_revision('30000000-0000-0000-0000-0000000000b4', '   '); exception when sqlstate '22023' then ok := true; end;
  if not coalesce(ok, false) then raise exception 'a rejection without reason was accepted'; end if;
  ok := false;
  begin perform public.reject_revision('30000000-0000-0000-0000-0000000000b4', repeat('x', 1001)); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a 1001 character reason was accepted'; end if;
  perform public.reject_revision('30000000-0000-0000-0000-0000000000b4', '  Promete curar una enfermedad; reformulá el titular.  ');
  ok := false;
  begin perform public.reject_revision('30000000-0000-0000-0000-0000000000b4', 'otra vez'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a rejected revision was rejected again'; end if;
  ok := false;
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000b4'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a rejected revision was approved'; end if;
end
$$;
reset role;
reset session authorization;
do $$
begin
  if (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2') <> 'Titular nuevo' then
    raise exception 'a rejection changed the live profile';
  end if;
  if (select count(*) from public.moderation_events where revision_id = '30000000-0000-0000-0000-0000000000b4'
        and revision_status_id = (select id from public.revision_statuses where code = 'rejected')
        and reason = 'Promete curar una enfermedad; reformulá el titular.'
        and actor_person_id = '10000000-0000-0000-0000-0000000000d4') <> 1 then
    raise exception 'rejection event missing or wrong (the reason must be trimmed)';
  end if;
end
$$;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
begin
  if (select rejection_reason from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000b4') is distinct from
     'Promete curar una enfermedad; reformulá el titular.' then
    raise exception 'the therapist must be able to read the rejection reason';
  end if;
end
$$;
reset role;
reset session authorization;

-- 5) STATES and PEOPLE: suspended and paused profiles, drafts, unknown ids
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000c3', 'c3', '{"headline":"Suspendido"}');
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000f6', 'f6', '{"headline":"Pausado cambia"}');
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a2', 'a1', '{"headline":"Borrador"}', 'draft');
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000c3'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a suspended profile was approved'; end if;
  ok := false;
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000a2'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a draft was approved'; end if;
  ok := false;
  begin perform public.reject_revision('30000000-0000-0000-0000-0000000000a2', 'x'); exception when sqlstate '55000' then ok := true; end;
  if not ok then raise exception 'a draft was rejected'; end if;
  ok := false;
  begin perform public.approve_revision(gen_random_uuid()); exception when sqlstate 'P0002' then ok := true; end;
  if not ok then raise exception 'an unknown revision gave the wrong error'; end if;
  -- a paused profile stays paused after approval / un perfil pausado sigue pausado
  perform public.approve_revision('30000000-0000-0000-0000-0000000000f6');
end
$$;
reset role;
reset session authorization;
do $$
begin
  if (select ps.code from public.therapist_profiles tp join public.profile_statuses ps on ps.id = tp.status_id
       where tp.id = '20000000-0000-0000-0000-0000000000f6') <> 'paused' then raise exception 'a paused profile changed status'; end if;
  if (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000f6') <> 'Pausado cambia' then
    raise exception 'the paused profile change was not applied';
  end if;
end
$$;

-- 6) SELF-APPROVAL is blocked unless the setting allows it / AUTOAPROBACIÓN bloqueada salvo que el ajuste la permita
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000e5', 'e5', '{"headline":"Admin se aprueba"}');
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000e5'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'an admin approved their own profile revision'; end if;
end
$$;
reset role;
reset session authorization;
update public.app_settings set value = 'true' where key = 'moderation_allow_self_approval';
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000000e5');
reset role;
reset session authorization;
do $$
begin
  if (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000e5') <> 'Admin se aprueba' then
    raise exception 'self approval did not apply when allowed';
  end if;
end
$$;
update public.app_settings set value = 'false' where key = 'moderation_allow_self_approval';
do $$
declare ok boolean := false;
begin
  begin update public.app_settings set value = '"yes"' where key = 'moderation_allow_self_approval'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a non boolean self approval setting was accepted'; end if;
end
$$;

-- 7) NON-ADMINS and anon cannot decide / los no-admin y anon no deciden
delete from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a2';
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a3', 'a1', '{"headline":"Intento"}');
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000a3'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist approved a revision'; end if;
  ok := false;
  begin perform public.reject_revision('30000000-0000-0000-0000-0000000000a3', 'x'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist rejected a revision'; end if;
  ok := false;
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000b2'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a therapist approved the revision of another'; end if;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);  -- a login that is not a person at all / un login que no es persona
do $$
declare ok boolean := false;
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000000a3'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a login without person approved a revision'; end if;
end
$$;
reset role;
reset session authorization;
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare stmt text; denied boolean;
begin
  foreach stmt in array array[
    $q$select public.approve_revision(gen_random_uuid())$q$,
    $q$select public.reject_revision(gen_random_uuid(), 'x')$q$,
    $q$select public.apply_revision_payload(gen_random_uuid(), '{}')$q$,
    $q$select public.revision_int('1'::jsonb, 'x')$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;
-- the revision of A stayed pending / la revisión de A siguió pendiente
do $$
begin
  if (select rs.code from public.profile_revisions r join public.revision_statuses rs on rs.id = r.status_id
       where r.id = '30000000-0000-0000-0000-0000000000a3') <> 'pending_review' then raise exception 'a denied call changed a revision'; end if;
end
$$;

-- 8) Function permissions / permisos de funciones
do $$
declare f text;
begin
  foreach f in array array['public.approve_revision(uuid)', 'public.reject_revision(uuid,text)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
  end loop;
  foreach f in array array['public.apply_revision_payload(uuid,jsonb)', 'public.revision_int(jsonb,text)'] loop
    if has_function_privilege('authenticated', f, 'EXECUTE') or has_function_privilege('anon', f, 'EXECUTE')
       or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'an API role can execute the internal function %', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = 0 and a.privilege_type = 'EXECUTE')) then
    raise exception 'PUBLIC can execute a function in public';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
               and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')) then
    raise exception 'a security definer function has no fixed search_path';
  end if;
end
$$;

rollback;
\echo 'OK: approval and rejection are admin-only, atomic and audited / aprobar y rechazar es solo de admin, atómico y auditado'
