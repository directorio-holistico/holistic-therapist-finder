-- Public display name: default from the person, required to publish, changed only through a moderated revision.
-- Nombre público: por defecto el de la persona, obligatorio para publicar, cambia solo con una revisión moderada.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test', now()),  -- therapist, published
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test', now()),  -- therapist, unpublished, long name
  ('00000000-0000-0000-0000-0000000000d4', 'd@example.test', now()),  -- admin
  ('00000000-0000-0000-0000-0000000000f6', 'f@example.test', now());  -- registers through the function
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Ana Pérez', 'a@example.test'),
  ('10000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2', repeat('x', 79) || ' ' || repeat('y', 30), 'b@example.test'),
  ('10000000-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000000d4', 'Admin D', 'd@example.test');
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000d4'::uuid, id from public.roles where code = 'admin';

-- 1) Default at creation (owner inserts, as the server does) / Valor por defecto al crear
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id)
  select '20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a1',
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '30 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1);
insert into public.therapist_profiles (id, person_id, status_id)
  select '20000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-0000000000b2', (select id from public.profile_statuses where code = 'unpublished');
insert into public.profile_contacts (profile_id, contact_type_id, value)
  values ('20000000-0000-0000-0000-0000000000a1', (select id from public.contact_types where code = 'phone'), '+54 351 555 0102');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = '20000000-0000-0000-0000-0000000000a1';

do $$
declare ok boolean;
begin
  if (select display_name from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') <> 'Ana Pérez' then
    raise exception 'the display name must start as the person name';
  end if;
  -- long names are cut to 80 and never end with a space (the CHECK would reject it)
  if (select display_name from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2') <> repeat('x', 79) then
    raise exception 'a long name must be cut to 80 characters without trailing spaces: [%]', (select display_name from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000b2');
  end if;
  -- constraints / restricciones
  ok := false; begin update public.therapist_profiles set display_name = '' where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an empty display name was accepted'; end if;
  ok := false; begin update public.therapist_profiles set display_name = repeat('x', 81) where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an 81 character display name was accepted'; end if;
  ok := false; begin update public.therapist_profiles set display_name = ' Ana ' where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a display name with spaces around was accepted'; end if;
  -- a published profile cannot lose its display name / un perfil publicado no pierde su nombre
  ok := false; begin update public.therapist_profiles set display_name = null where id = '20000000-0000-0000-0000-0000000000a1'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a published profile lost its display name'; end if;
  -- an unpublished profile may have none, but then it cannot be published / sin nombre no se publica
  update public.therapist_profiles set display_name = null where id = '20000000-0000-0000-0000-0000000000b2';
  update public.therapist_profiles set approved_at = now(), location_id = (select location_id from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1')
    where id = '20000000-0000-0000-0000-0000000000b2';
  insert into public.profile_contacts (profile_id, contact_type_id, value)
    values ('20000000-0000-0000-0000-0000000000b2', (select id from public.contact_types where code = 'phone'), '+54 351 555 0103');
  ok := false;
  begin update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = '20000000-0000-0000-0000-0000000000b2';
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a profile without display name was published'; end if;
  update public.therapist_profiles set display_name = 'Beto' where id = '20000000-0000-0000-0000-0000000000b2';
end
$$;

-- 2) register_therapist gives the new profile the registered name / el alta da al perfil el nombre registrado
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f6","role":"authenticated"}', true);
select public.register_therapist('Flor Gómez', '{"terms":"1","privacy":"1","legal_declaration":"1"}');
do $$
begin
  if (select display_name from public.therapist_profiles) is distinct from 'Flor Gómez' then
    raise exception 'a registered profile must start with the registered name';
  end if;
end
$$;
-- the API cannot write it directly (only through a revision) / la API no lo escribe directo
do $$
declare denied boolean := false;
begin
  begin update public.therapist_profiles set display_name = 'Hackeado'; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'a therapist wrote display_name directly'; end if;
end
$$;
reset role;
reset session authorization;

-- 3) Revisions: the name travels in the payload, is flagged and moderated like the rest
create function pg_temp.open_revision(p_id uuid, p_profile text, p_payload jsonb) returns void language sql as $$
  insert into public.profile_revisions (id, profile_id, status_id, payload, submitted_at, due_at)
  values (p_id, ('20000000-0000-0000-0000-0000000000' || p_profile)::uuid,
          (select id from public.revision_statuses where code = 'draft'), p_payload, null, null);
$$;
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a1', 'a1', '{"display_name":"Ana, maestra de la curación"}');
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare flagged text[];
begin
  -- a revision with only the name is valid, and its words are checked against the restricted terms
  flagged := public.submit_revision('30000000-0000-0000-0000-0000000000a1');
  if flagged <> array['curacion'] then raise exception 'the display name must be checked against restricted terms: %', flagged; end if;
end
$$;
reset role;
reset session authorization;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000000a1');
reset role;
reset session authorization;
do $$
begin
  if (select display_name from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') <> 'Ana, maestra de la curación' then
    raise exception 'the approved display name was not applied';
  end if;
end
$$;

-- 4) Invalid names in a revision: all-or-nothing, as before / nombres inválidos: todo o nada
create function pg_temp.try_bad(p_label text, p_payload jsonb, p_expected text) returns void
language plpgsql as $$
declare accepted boolean := false; state text;
begin
  update public.profile_revisions set payload = p_payload, status_id = (select id from public.revision_statuses where code = 'pending_review'),
    closed_at = null, decided_at = null, submitted_at = now(), due_at = now() + interval '3 days'
    where id = '30000000-0000-0000-0000-0000000000a2';
  begin
    set local role authenticated;
    perform public.approve_revision('30000000-0000-0000-0000-0000000000a2');
    accepted := true;
  exception when others then
    state := sqlstate;
    if state <> p_expected then raise exception 'case [%]: expected %, got % (%)', p_label, p_expected, state, sqlerrm; end if;
  end;
  reset role;
  if accepted then raise exception 'case [%] was accepted', p_label; end if;
  if (select display_name from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') <> 'Ana, maestra de la curación'
     or (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') is not null then
    raise exception 'case [%] left a partial change', p_label;
  end if;
end $$;
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a2', 'a1', '{"headline":"No debe aplicarse"}');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
begin
  perform pg_temp.try_bad('null name on a published profile', '{"headline":"No debe aplicarse","display_name":null}', '23514');
  perform pg_temp.try_bad('name as number', '{"headline":"No debe aplicarse","display_name":5}', '22023');
  perform pg_temp.try_bad('name too long', jsonb_build_object('headline', 'No debe aplicarse', 'display_name', repeat('z', 81)), '23514');
  perform pg_temp.try_bad('name with spaces around', '{"headline":"No debe aplicarse","display_name":" Ana "}', '23514');
end
$$;
-- submit still refuses unknown keys, and still accepts the new one / submit sigue rechazando claves desconocidas
update public.profile_revisions set status_id = (select id from public.revision_statuses where code = 'draft'),
  submitted_at = null, due_at = null, payload = '{"is_admin":true}' where id = '30000000-0000-0000-0000-0000000000a2';
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.submit_revision('30000000-0000-0000-0000-0000000000a2'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an unknown key was accepted at submission'; end if;
end
$$;
reset role;
reset session authorization;

-- 5) Permissions are the same as before the replacement / los permisos siguen igual
do $$
declare f text;
begin
  foreach f in array array['public.submit_revision(uuid)', 'public.approve_revision(uuid)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
  end loop;
  foreach f in array array['public.apply_revision_payload(uuid,jsonb)', 'public.therapist_profiles_guard()'] loop
    if has_function_privilege('authenticated', f, 'EXECUTE') or has_function_privilege('anon', f, 'EXECUTE')
       or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'an API role can execute %', f;
    end if;
  end loop;
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
\echo 'OK: public display name defaults, is required to publish and changes only through moderation / nombre publico por defecto, obligatorio para publicar y solo cambia con moderacion'
