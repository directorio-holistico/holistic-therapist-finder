-- Reports and suspension: who can create, read and close reports; who can suspend; what is recorded.
-- Denuncias y suspensión: quién crea, lee y cierra denuncias; quién suspende; qué queda registrado.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000003' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2','a3','a4','a5','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000003' || k)::uuid, ('00000000-0000-0000-0000-0000000003' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2','a3','a4','a5','ad']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000003ad'::uuid, id from public.roles where code = 'admin';

-- a1 published | a2 published | a3 paused | a4 unpublished (never approved) | a5 erased
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000003' || k)::uuid, ('10000000-0000-0000-0000-0000000003' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'),
         case when k = 'a4' then null else now() - interval '20 days' end,
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1), 'Perfil ' || k
  from unnest(array['a1','a2','a3','a4','a5']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000003' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+54 351 555 0' || n
  from unnest(array['a1','a2','a3','a4','a5']) with ordinality as u(k, n);
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000003a1', '20000000-0000-0000-0000-0000000003a2', '20000000-0000-0000-0000-0000000003a3');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused') where id = '20000000-0000-0000-0000-0000000003a3';
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'erased') where id = '20000000-0000-0000-0000-0000000003a5';

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare f text;
begin
  if (select count(*) from public.report_reasons) <> 6 or (select count(*) from public.report_statuses) <> 3 then
    raise exception 'the catalogs of reasons (6) and statuses (3) are incomplete';
  end if;
  if exists (select 1 from pg_class c where c.oid in ('public.reports'::regclass, 'public.report_reasons'::regclass, 'public.report_statuses'::regclass) and not c.relrowsecurity) then
    raise exception 'a report table has no RLS';
  end if;
  -- nobody writes the report tables through the API / nadie escribe las tablas por la API
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public'
              and table_name in ('reports', 'report_reasons', 'report_statuses') and grantee in ('anon', 'authenticated', 'public')
              and privilege_type <> 'SELECT') then
    raise exception 'an API role can write a report table';
  end if;
  if has_table_privilege('anon', 'public.reports', 'select') or has_table_privilege('anon', 'public.report_reasons', 'select') then
    raise exception 'anon can read the report tables';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'reports' and column_name ~* '(ip|session|agent|device)') then
    raise exception 'reports must carry no network identifier';
  end if;
  -- ACL matrix of the 5 functions / matriz de permisos de las 5 funciones
  if not has_function_privilege('service_role', 'public.report_profile(uuid,text,text,text)', 'execute')
     or has_function_privilege('anon', 'public.report_profile(uuid,text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.report_profile(uuid,text,text,text)', 'execute') then
    raise exception 'report_profile must be executable by service_role only';
  end if;
  foreach f in array array['public.close_report(bigint,text,text)', 'public.suspend_profile(uuid,text)', 'public.reinstate_profile(uuid,text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') or has_function_privilege('service_role', f, 'execute') then
      raise exception '% must be executable by authenticated only', f;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.purge_expired_reports()', 'execute') or has_function_privilege('authenticated', 'public.purge_expired_reports()', 'execute')
     or not has_function_privilege('service_role', 'public.purge_expired_reports()', 'execute') then
    raise exception 'purge_expired_reports must be executable by service_role only';
  end if;
end $$;

-- 2) CREATE REPORTS as the server (service_role) / CREAR DENUNCIAS como el servidor
set session authorization authenticator;
set role service_role;
do $$
declare
  a1 uuid := '20000000-0000-0000-0000-0000000003a1'; id1 bigint; id2 bigint;
  q text; failed int := 0;
begin
  id1 := public.report_profile(a1, 'cure_claim', '  Promete curar el cáncer  ', ' Ana@Example.TEST ');
  id2 := public.report_profile(a1, 'other');
  perform public.report_profile('20000000-0000-0000-0000-0000000003a2', 'false_information', '   ', '');
  perform set_config('test.id1', id1::text, true); perform set_config('test.id2', id2::text, true);
  -- invalid input: all rejected with 22023 (same message for unknown, hidden or null profile)
  foreach q in array array[
    $q$select public.report_profile(null, 'other')$q$,
    $q$select public.report_profile('99999999-9999-9999-9999-999999999999', 'other')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a3', 'other')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a4', 'other')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a5', 'other')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a1', 'inventado')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a1', null)$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a1', 'other', repeat('x', 1001))$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a1', 'other', null, 'sin-arroba')$q$,
    $q$select public.report_profile('20000000-0000-0000-0000-0000000003a1', 'other', null, repeat('a', 250) || '@x.co')$q$] loop
    begin
      execute q;
      raise exception 'accepted: %', q;
    exception when sqlstate '22023' then failed := failed + 1;
    end;
  end loop;
  if failed <> 10 then raise exception 'expected 10 rejections, got %', failed; end if;
  -- a 1000-character detail is the maximum accepted / 1000 caracteres es el máximo aceptado
  perform public.report_profile(a1, 'other', repeat('y', 1000));
end $$;
reset role;
reset session authorization;

-- 2b) WHAT WAS STORED (as owner; service_role has no read access) / LO GUARDADO (como dueño)
do $$
declare id1 bigint := current_setting('test.id1')::bigint; id2 bigint := current_setting('test.id2')::bigint;
begin
  if (select details || '|' || reporter_email from public.reports where id = id1) is distinct from 'Promete curar el cáncer|ana@example.test' then
    raise exception 'details and email must be trimmed, email lower case'; end if;
  if (select details is null and reporter_email is null from public.reports where id = id2) is not true then raise exception 'optional fields must be null'; end if;
  if (select details is null and reporter_email is null from public.reports where profile_id = '20000000-0000-0000-0000-0000000003a2') is not true then
    raise exception 'blank details/email must become null'; end if;
  if exists (select 1 from public.reports r join public.report_statuses s on s.id = r.status_id where s.code <> 'open' or r.resolved_at is not null) then
    raise exception 'new reports must be open'; end if;
  if (select count(*) from public.reports) <> 4 then raise exception 'expected 4 reports (3 valid + the 1000-character one), rejected ones left rows'; end if;
end $$;

-- 2c) A DEACTIVATED REASON IS NOT ACCEPTED / UN MOTIVO DESACTIVADO NO SE ACEPTA
update public.report_reasons set is_active = false where code = 'other';
set session authorization authenticator;
set role service_role;
do $$
begin
  begin perform public.report_profile('20000000-0000-0000-0000-0000000003a1', 'other'); raise exception 'a deactivated reason was accepted';
  exception when sqlstate '22023' then null; end;
  perform public.report_profile('20000000-0000-0000-0000-0000000003a1', 'cure_claim');   -- active ones still work / los activos siguen
end $$;
reset role;
reset session authorization;
update public.report_reasons set is_active = true where code = 'other';
delete from public.reports where id = (select max(id) from public.reports);   -- remove the extra row / saco la fila extra

-- 3) NO OTHER ROLE CREATES REPORTS / NINGÚN OTRO ROL CREA DENUNCIAS
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform public.report_profile('20000000-0000-0000-0000-0000000003a1', 'other'); raise exception 'anon created a report';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.reports; raise exception 'anon read reports';
  exception when insufficient_privilege then null; end;
  begin insert into public.reports (reason_id, status_id) values (1, 1); raise exception 'anon wrote reports';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 4) THERAPIST: sees no report, creates none, cannot close, suspend or reinstate / TERAPEUTA
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a1","role":"authenticated"}', true);
do $$
declare r bigint := (select min(id) from (select id from public.reports) s);
begin
  if (select count(*) from public.reports) <> 0 then raise exception 'a therapist sees reports (even about their own profile)'; end if;
  begin perform public.report_profile('20000000-0000-0000-0000-0000000003a2', 'other'); raise exception 'authenticated created a report';
  exception when insufficient_privilege then null; end;
  begin insert into public.reports (reason_id, status_id) values (1, 1); raise exception 'authenticated wrote reports';
  exception when insufficient_privilege then null; end;
  begin perform public.close_report(1, 'dismissed', 'x'); raise exception 'a therapist closed a report';
  exception when sqlstate '42501' then null; end;
  begin perform public.suspend_profile('20000000-0000-0000-0000-0000000003a2', 'x'); raise exception 'a therapist suspended a profile';
  exception when sqlstate '42501' then null; end;
  begin perform public.suspend_profile('20000000-0000-0000-0000-0000000003a1', 'x'); raise exception 'a therapist suspended their own profile';
  exception when sqlstate '42501' then null; end;
  begin perform public.reinstate_profile('20000000-0000-0000-0000-0000000003a1', 'x'); raise exception 'a therapist reinstated a profile';
  exception when sqlstate '42501' then null; end;
  begin perform public.purge_expired_reports(); raise exception 'authenticated ran the purge';
  exception when insufficient_privilege then null; end;
  begin update public.report_reasons set is_active = false; raise exception 'authenticated changed a catalog';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 5) ADMIN: reads, closes, suspends, reinstates / ADMIN
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003ad","role":"authenticated"}', true);
do $$
declare
  rid bigint := (select min(id) from public.reports);
  a1 uuid := '20000000-0000-0000-0000-0000000003a1'; a2 uuid := '20000000-0000-0000-0000-0000000003a2';
  a3 uuid := '20000000-0000-0000-0000-0000000003a3'; a4 uuid := '20000000-0000-0000-0000-0000000003a4';
  a5 uuid := '20000000-0000-0000-0000-0000000003a5';
begin
  if (select count(*) from public.reports) <> 4 then raise exception 'the admin should read the 4 reports'; end if;

  -- close_report / cerrar denuncia
  begin perform public.close_report(rid, 'dismissed', '   '); raise exception 'blank note accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.close_report(rid, 'open', 'x'); raise exception 'closing as open accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.close_report(rid, null, 'x'); raise exception 'null status accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.close_report(rid, 'dismissed', repeat('x', 1001)); raise exception 'long note accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.close_report(999999, 'dismissed', 'x'); raise exception 'unknown report accepted'; exception when sqlstate 'P0002' then null; end;
  perform public.close_report(rid, 'resolved', '  Se suspendió el perfil  ');
  if (select s.code || '|' || r.resolution_note || '|' || coalesce((r.resolved_by_person_id = '10000000-0000-0000-0000-0000000003ad')::text, 'NULL') || '|' || (r.resolved_at is not null)::text
        from public.reports r join public.report_statuses s on s.id = r.status_id where r.id = rid) is distinct from 'resolved|Se suspendió el perfil|true|true' then
    raise exception 'closing did not record status, note, admin and date';
  end if;
  begin perform public.close_report(rid, 'dismissed', 'otra vez'); raise exception 'closed twice'; exception when sqlstate '55000' then null; end;
  perform public.close_report(rid + 1, 'dismissed', 'Sin fundamento');
  -- closing a report does not touch the profile / cerrar una denuncia no toca el perfil
  if (select s.code from public.therapist_profiles tp join public.profile_statuses s on s.id = tp.status_id where tp.id = a1) <> 'published' then
    raise exception 'closing a report changed the profile'; end if;

  -- suspend_profile
  begin perform public.suspend_profile(a1, '  '); raise exception 'blank reason accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.suspend_profile(a1, repeat('x', 501)); raise exception 'reason over 500 accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.suspend_profile('99999999-9999-9999-9999-999999999999', 'x'); raise exception 'unknown profile accepted'; exception when sqlstate 'P0002' then null; end;
  begin perform public.suspend_profile(a5, 'x'); raise exception 'an erased profile was suspended'; exception when sqlstate '55000' then null; end;
  perform public.suspend_profile(a1, '  Promete curar enfermedades  ');
  perform public.suspend_profile(a3, 'Pausado y además denunciado');   -- from paused / desde pausado
  perform public.suspend_profile(a4, 'Bloqueo antes de aprobar');      -- from unpublished / desde no publicado
  begin perform public.suspend_profile(a1, 'otra vez'); raise exception 'suspended twice'; exception when sqlstate '55000' then null; end;
  if (select string_agg(s.code || ':' || coalesce(tp.status_reason, '-'), ',' order by tp.id) from public.therapist_profiles tp
        join public.profile_statuses s on s.id = tp.status_id where tp.id in (a1, a3, a4))
     <> 'suspended:Promete curar enfermedades,suspended:Pausado y además denunciado,suspended:Bloqueo antes de aprobar' then
    raise exception 'suspension did not set status and reason';
  end if;
  -- the other profile is untouched / el otro perfil no cambia
  if (select s.code from public.therapist_profiles tp join public.profile_statuses s on s.id = tp.status_id where tp.id = a2) <> 'published' then
    raise exception 'suspending touched another profile'; end if;
  -- the decision is recorded: who, when, why / la decisión queda registrada
  if (select count(*) from public.moderation_events me join public.profile_statuses s on s.id = me.profile_status_id
       where s.code = 'suspended' and me.actor_person_id = '10000000-0000-0000-0000-0000000003ad' and me.profile_id in (a1, a3, a4)) <> 3 then
    raise exception 'suspensions must write one moderation event each'; end if;
  if (select me.reason from public.moderation_events me where me.profile_id = a1) <> 'Promete curar enfermedades' then raise exception 'event reason'; end if;

  -- reinstate_profile
  begin perform public.reinstate_profile(a2, 'x'); raise exception 'a published profile was "reinstated"'; exception when sqlstate '55000' then null; end;
  begin perform public.reinstate_profile(a1, ' '); raise exception 'blank reason accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.reinstate_profile('99999999-9999-9999-9999-999999999999', 'x'); raise exception 'unknown profile accepted'; exception when sqlstate 'P0002' then null; end;
  perform public.reinstate_profile(a1, 'Corrigió el texto');
  perform public.reinstate_profile(a4, 'Se levanta el bloqueo');
  if (select s.code || ':' || coalesce(tp.status_reason, '-') from public.therapist_profiles tp join public.profile_statuses s on s.id = tp.status_id where tp.id = a1) <> 'published:-' then
    raise exception 'an approved profile must go back to published with no reason'; end if;
  if (select s.code from public.therapist_profiles tp join public.profile_statuses s on s.id = tp.status_id where tp.id = a4) <> 'unpublished' then
    raise exception 'a never-approved profile must go back to unpublished'; end if;
  if (select count(*) from public.moderation_events me join public.profile_statuses s on s.id = me.profile_status_id
       where s.code in ('published', 'unpublished') and me.actor_person_id = '10000000-0000-0000-0000-0000000003ad' and me.profile_id in (a1, a4)) <> 2 then
    raise exception 'reinstating must write one moderation event each'; end if;
  begin perform public.report_profile(a1, 'other'); raise exception 'admin as authenticated created a report'; exception when insufficient_privilege then null; end;
  begin update public.reports set resolution_note = 'x'; raise exception 'admin updated reports through the API'; exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 6) VISIBILITY: a suspended profile cannot be reported and is hidden from the public views / VISIBILIDAD
do $$
declare a3 uuid := '20000000-0000-0000-0000-0000000003a3';
begin
  if exists (select 1 from public.public_profile_cards where profile_id = a3) then raise exception 'a suspended profile is still public'; end if;
  if not exists (select 1 from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000003a1') then
    raise exception 'the reinstated profile must be public again'; end if;
end $$;
set session authorization authenticator;
set role service_role;
do $$
begin
  begin perform public.report_profile('20000000-0000-0000-0000-0000000003a3', 'other'); raise exception 'a suspended profile was reported';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
reset session authorization;

-- 7) TABLE CONSTRAINTS (as owner) / RESTRICCIONES DE LA TABLA
do $$
begin
  begin update public.reports set resolution_note = 'x' where id = (select min(id) from public.reports where resolved_at is null) ; raise exception 'note without date accepted';
  exception when check_violation then null; end;
  begin update public.reports set resolved_at = now() where id = (select min(id) from public.reports where resolved_at is null); raise exception 'date without note accepted';
  exception when check_violation then null; end;
  begin update public.reports set reporter_email = 'Mayus@x.co' where id = (select min(id) from public.reports); raise exception 'upper case email accepted';
  exception when check_violation then null; end;
  begin update public.reports set details = ' con espacios ' where id = (select min(id) from public.reports); raise exception 'untrimmed details accepted';
  exception when check_violation then null; end;
end $$;

-- 8) RETENTION and CASCADE / RETENCIÓN y CASCADA
do $$
declare open_id smallint := (select id from public.report_statuses where code = 'open'); res_id smallint := (select id from public.report_statuses where code = 'resolved');
begin
  insert into public.reports (profile_id, reason_id, status_id, created_at, resolved_at, resolution_note) values
    ('20000000-0000-0000-0000-0000000003a2', 1, res_id, now() - interval '500 days', now() - interval '400 days', 'viejo'),
    ('20000000-0000-0000-0000-0000000003a2', 1, res_id, now() - interval '300 days', now() - interval '200 days', 'reciente'),
    ('20000000-0000-0000-0000-0000000003a2', 1, open_id, now() - interval '900 days', null, null);
end $$;
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_reports();
  if removed <> 1 then raise exception 'purge should remove only the old closed report, removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
declare n_before int; n_after int;
begin
  if not exists (select 1 from public.reports where resolution_note = 'reciente') then raise exception 'purge removed a recent closed report'; end if;
  if (select count(*) from public.reports r join public.report_statuses s on s.id = r.status_id where s.code = 'open' and r.created_at < now() - interval '800 days') <> 1 then
    raise exception 'purge removed an old OPEN report'; end if;
  begin update public.app_settings set value = '0' where key = 'retention_reports_months'; raise exception 'retention 0 accepted'; exception when check_violation then null; end;
  begin update public.app_settings set value = 'true' where key = 'retention_reports_months'; raise exception 'retention boolean accepted'; exception when check_violation then null; end;
  if (select is_public from public.app_settings where key = 'retention_reports_months') then raise exception 'retention setting must be private'; end if;
  -- deleting a profile keeps its reports, with no profile / borrar un perfil conserva sus denuncias sin perfil
  select count(*) into n_before from public.reports where profile_id = '20000000-0000-0000-0000-0000000003a2';
  delete from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000003a2';
  select count(*) into n_after from public.reports where profile_id is null;
  if n_before = 0 or n_after < n_before then raise exception 'reports of a deleted profile must stay with a null profile'; end if;
end $$;

rollback;
select 'OK 15-reports-suspension' as result;
