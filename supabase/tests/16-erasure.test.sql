-- Erasure of a therapist: what disappears, what stays, who can run it, the fingerprints.
-- Eliminación de un terapeuta: qué desaparece, qué queda, quién puede correrla, las huellas.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000004' || k)::uuid, 'canario-' || k || '@example.test', now() from unnest(array['a1','a2','a3','a4','a5','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000004' || k)::uuid, ('00000000-0000-0000-0000-0000000004' || k)::uuid, 'Persona CANARIO-' || upper(k), 'canario-' || k || '@example.test'
  from unnest(array['a1','a2','a3','a4','a5','ad']) k;
insert into public.person_roles (person_id, role_id)
  select ('10000000-0000-0000-0000-0000000004' || k)::uuid, (select id from public.roles where code = case when k = 'ad' then 'admin' else 'therapist' end)
  from unnest(array['a1','a2','a3','a4','a5','ad']) k;

-- profiles a1, a2, a4 published (a3 and a5 have a person but no profile; ad is the admin)
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name, headline, photo_path)
  select ('20000000-0000-0000-0000-0000000004' || k)::uuid, ('10000000-0000-0000-0000-0000000004' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '20 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
         'Perfil CANARIO-' || upper(k), 'Titular CANARIO-' || upper(k), ('20000000-0000-0000-0000-0000000004' || k) || '/foto-canario-' || k || '.png'
  from unnest(array['a1','a2','a4']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select ('20000000-0000-0000-0000-0000000004' || x.k)::uuid, ct.id, x.v, x.w
  from (values ('a1','phone','+54 351 555 0001',true), ('a1','email','canario-a1-pro@example.test',false), ('a1','website','https://example.test/canario-a1',false),
               ('a2','phone','+54 (351) 555-0001',false), ('a2','email','canario-a2-pro@example.test',false),
               ('a4','phone','+54 351 555 0004',false)) x(k, t, v, w)
  join public.contact_types ct on ct.code = x.t;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000004a1', '20000000-0000-0000-0000-0000000004a2', '20000000-0000-0000-0000-0000000004a4');
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select ('20000000-0000-0000-0000-0000000004' || k)::uuid, (select id from public.therapies where is_active order by id limit 1), 60 from unnest(array['a1','a2','a4']) k;
insert into public.profile_revisions (profile_id, status_id, payload)
  values ('20000000-0000-0000-0000-0000000004a1', (select id from public.revision_statuses where code = 'draft'), '{"headline":"Borrador CANARIO-A1"}');
insert into public.contact_reveals (profile_id, day) values ('20000000-0000-0000-0000-0000000004a1', current_date), ('20000000-0000-0000-0000-0000000004a4', current_date);
insert into public.reports (profile_id, reason_id, details, reporter_email, status_id) values
  ('20000000-0000-0000-0000-0000000004a1', (select id from public.report_reasons where code = 'other'), 'Denuncia con CANARIO-A1 en el texto', 'denunciante@example.test', (select id from public.report_statuses where code = 'open')),
  ('20000000-0000-0000-0000-0000000004a4', (select id from public.report_reasons where code = 'other'), 'Denuncia sobre a4', null, (select id from public.report_statuses where code = 'open'));
insert into public.terms_acceptances (person_id, document_type_id, version)
  values ('10000000-0000-0000-0000-0000000004a1', (select id from public.legal_document_types where code = 'terms'), 'v1');
insert into public.moderation_events (profile_id, actor_person_id, profile_status_id, reason)
  values ('20000000-0000-0000-0000-0000000004a1', '10000000-0000-0000-0000-0000000004ad', (select id from public.profile_statuses where code = 'published'), 'Revisión previa');

create function pg_temp.h(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
select set_config('test.fp_a1', jsonb_build_array(
    jsonb_build_object('type', 'email', 'hash', pg_temp.h('canario-a1@example.test')),
    jsonb_build_object('type', 'email', 'hash', pg_temp.h('canario-a1-pro@example.test')),
    jsonb_build_object('type', 'phone', 'hash', pg_temp.h('543515550001')))::text, true),
  set_config('test.fp_a2', jsonb_build_array(
    jsonb_build_object('type', 'email', 'hash', pg_temp.h('canario-a2@example.test')),
    jsonb_build_object('type', 'phone', 'hash', pg_temp.h('543515550001')))::text, true),   -- same phone as a1 / mismo teléfono que a1
  set_config('test.fp_a3', jsonb_build_array(jsonb_build_object('type', 'email', 'hash', pg_temp.h('canario-a3@example.test')))::text, true),
  set_config('test.h_a1_phone', pg_temp.h('543515550001'), true),
  set_config('test.h_a1_email', pg_temp.h('canario-a1@example.test'), true),
  set_config('test.h_a3_email', pg_temp.h('canario-a3@example.test'), true);

-- helper: count public rows whose text contains a canary / ayuda: filas públicas cuyo texto contiene una marca
create function pg_temp.canary_rows(p_canary text) returns text language plpgsql as $$
declare t text; n bigint; found text := '';
begin
  for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    execute format('select count(*) from public.%I x where x::text ilike %L', t, '%' || p_canary || '%') into n;
    if n > 0 then found := found || t || ':' || n || ' '; end if;
  end loop;
  return found;
end $$;

-- 1) STRUCTURE and ACL (as owner) / ESTRUCTURA y PERMISOS
do $$
declare f text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.erasure_fingerprints'::regclass) then raise exception 'erasure_fingerprints has no RLS'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'erasure_fingerprints'
              and grantee in ('anon', 'authenticated', 'service_role', 'public')) then
    raise exception 'an API role has a grant on erasure_fingerprints';
  end if;
  if exists (select 1 from pg_policy where polrelid = 'public.erasure_fingerprints'::regclass) then raise exception 'erasure_fingerprints must have no policy'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'erasure_fingerprints'
              and column_name ~* '(person|user|email|phone|name|value)') then
    raise exception 'erasure_fingerprints must link to no person and hold no raw value';
  end if;
  foreach f in array array['public.erasure_material(uuid)', 'public.erase_therapist(uuid,jsonb,text)', 'public.check_erasure_fingerprints(jsonb)', 'public.purge_expired_erasure_fingerprints()'] loop
    if not has_function_privilege('service_role', f, 'execute') or has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception '% must be executable by service_role only', f;
    end if;
  end loop;
  if has_function_privilege('service_role', 'public.parse_fingerprints(jsonb,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.parse_fingerprints(jsonb,boolean)', 'execute')
     or has_function_privilege('anon', 'public.parse_fingerprints(jsonb,boolean)', 'execute') then
    raise exception 'parse_fingerprints is internal: no API role may run it';
  end if;
  if (select is_public from public.app_settings where key = 'retention_erasure_fingerprints_months') then raise exception 'retention setting must be private'; end if;
  -- the scan itself works: before erasing, the canary of a1 is everywhere / el escaneo funciona: antes de eliminar, la marca está en todos lados
  if (select count(*) from unnest(array['people:', 'therapist_profiles:', 'profile_contacts:', 'profile_revisions:', 'reports:']) k where position(k in pg_temp.canary_rows('canario-a1')) = 0) > 0 then
    raise exception 'the canary scan does not see the fixture: %', pg_temp.canary_rows('canario-a1');
  end if;
end $$;

-- 2) AS THE SERVER: material and invalid input / COMO EL SERVIDOR: material y entradas inválidas
set session authorization authenticator;
set role service_role;
do $$
declare
  a1 uuid := '10000000-0000-0000-0000-0000000004a1'; a3 uuid := '10000000-0000-0000-0000-0000000004a3'; ad uuid := '10000000-0000-0000-0000-0000000004ad';
  got text; q text; failed int := 0; good text := current_setting('test.fp_a1');
begin
  select string_agg(contact_type || '=' || value, ',' order by contact_type, value) into got from public.erasure_material(a1);
  if got <> 'email=canario-a1-pro@example.test,email=canario-a1@example.test,phone=543515550001' then raise exception 'material a1: %', got; end if;
  select string_agg(contact_type || '=' || value, ',') into got from public.erasure_material(a3);
  if got <> 'email=canario-a3@example.test' then raise exception 'material a3 (no profile): %', got; end if;
  if exists (select 1 from public.erasure_material('99999999-9999-9999-9999-999999999999')) then raise exception 'material of an unknown person'; end if;
  if exists (select 1 from public.erasure_material(null)) then raise exception 'material of null'; end if;

  foreach q in array array[
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', null, 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', '{}'::jsonb, 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', '[]'::jsonb, 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', '[{"type":"email","hash":"abc"}]'::jsonb, 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', jsonb_build_array(jsonb_build_object('type','email','hash',upper(repeat('a',64)))), 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', jsonb_build_array(jsonb_build_object('type','website','hash',repeat('a',64))), 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', jsonb_build_array(jsonb_build_object('type','email','hash',repeat('a',64),'extra',1)), 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', jsonb_build_array('texto'), 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', (select jsonb_agg(jsonb_build_object('type','email','hash',repeat(to_hex(g % 10), 64))) from generate_series(1, 21) g), 'self')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', current_setting('test.fp_a3')::jsonb, 'otro')$q$,
    $q$select * from public.erase_therapist('10000000-0000-0000-0000-0000000004a5', current_setting('test.fp_a3')::jsonb, null)$q$,
    $q$select public.check_erasure_fingerprints('[{"type":"email","hash":"x"}]'::jsonb)$q$,
    $q$select public.check_erasure_fingerprints(null)$q$] loop
    begin
      execute q;
      raise exception 'accepted: %', q;
    exception when sqlstate '22023' then failed := failed + 1;
    end;
  end loop;
  if failed <> 13 then raise exception 'expected 13 rejections (22023), got %', failed; end if;
  begin perform * from public.erase_therapist(null, good::jsonb, 'self'); raise exception 'null person accepted'; exception when sqlstate 'P0002' then null; end;
  begin perform * from public.erase_therapist('99999999-9999-9999-9999-999999999999', good::jsonb, 'self'); raise exception 'unknown person accepted'; exception when sqlstate 'P0002' then null; end;
  begin perform * from public.erase_therapist(ad, good::jsonb, 'admin'); raise exception 'an administrator was erased'; exception when sqlstate '55000' then null; end;
  if public.check_erasure_fingerprints('[]'::jsonb) <> 0 then raise exception 'empty check must be 0'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.erasure_fingerprints) <> 0 then raise exception 'rejected calls left fingerprints'; end if;
  if (select count(*) from public.people where erased_at is not null) <> 0 or (select count(*) from public.therapist_profiles) <> 3 then raise exception 'rejected calls changed data'; end if;
end $$;

-- 3) NO OTHER ROLE: anon, therapist, admin / NINGÚN OTRO ROL
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform * from public.erase_therapist('10000000-0000-0000-0000-0000000004a1', current_setting('test.fp_a1')::jsonb, 'self'); raise exception 'anon erased';
  exception when insufficient_privilege then null; end;
  begin perform * from public.erasure_material('10000000-0000-0000-0000-0000000004a1'); raise exception 'anon read material';
  exception when insufficient_privilege then null; end;
  begin perform public.check_erasure_fingerprints('[]'::jsonb); raise exception 'anon checked fingerprints';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.erasure_fingerprints; raise exception 'anon read fingerprints';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a1","role":"authenticated"}', true);
do $$
begin
  begin perform * from public.erase_therapist('10000000-0000-0000-0000-0000000004a1', current_setting('test.fp_a1')::jsonb, 'self'); raise exception 'a therapist erased themself through the API';
  exception when insufficient_privilege then null; end;
  begin perform * from public.erase_therapist('10000000-0000-0000-0000-0000000004a4', current_setting('test.fp_a1')::jsonb, 'self'); raise exception 'a therapist erased another';
  exception when insufficient_privilege then null; end;
  begin perform * from public.erasure_material('10000000-0000-0000-0000-0000000004a1'); raise exception 'authenticated read material';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.erasure_fingerprints; raise exception 'authenticated read fingerprints';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_erasure_fingerprints(); raise exception 'authenticated ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004ad","role":"authenticated"}', true);
do $$
begin
  begin perform * from public.erase_therapist('10000000-0000-0000-0000-0000000004a1', current_setting('test.fp_a1')::jsonb, 'admin'); raise exception 'an admin erased through the API (the server must do it)';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.erasure_fingerprints; raise exception 'the admin read fingerprints';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 4) ERASE a1 (as the server) / ELIMINAR a1
set session authorization authenticator;
set role service_role;
do $$
declare r record;
begin
  select * into r from public.erase_therapist('10000000-0000-0000-0000-0000000004a1', current_setting('test.fp_a1')::jsonb, 'self');
  if r.auth_user_id is distinct from '00000000-0000-0000-0000-0000000004a1'::uuid
     or r.profile_id is distinct from '20000000-0000-0000-0000-0000000004a1'::uuid
     or r.photo_path is distinct from '20000000-0000-0000-0000-0000000004a1/foto-canario-a1.png' then
    raise exception 'the cleanup data for the server is wrong: %', r;
  end if;
  begin perform * from public.erase_therapist('10000000-0000-0000-0000-0000000004a1', current_setting('test.fp_a1')::jsonb, 'self'); raise exception 'erased twice';
  exception when sqlstate '55000' then null; end;
end $$;
reset role;
reset session authorization;
do $$
declare a1p uuid := '20000000-0000-0000-0000-0000000004a1'; n int;
begin
  -- profile and children are gone / perfil e hijos borrados
  if exists (select 1 from public.therapist_profiles where id = a1p) then raise exception 'the profile survived'; end if;
  select count(*) into n from (select 1 from public.profile_contacts where profile_id = a1p union all select 1 from public.profile_therapies where profile_id = a1p
    union all select 1 from public.profile_revisions where profile_id = a1p union all select 1 from public.contact_reveals where profile_id = a1p) s;
  if n <> 0 then raise exception 'children of the profile survived: %', n; end if;
  -- the person is anonymized and has no role / la persona está anonimizada y sin roles
  if (select full_name || '|' || (email is null)::text || '|' || (auth_user_id is null)::text || '|' || (erased_at is not null)::text
        from public.people where id = '10000000-0000-0000-0000-0000000004a1') is distinct from 'Persona eliminada|true|true|true' then raise exception 'the person was not anonymized'; end if;
  if exists (select 1 from public.person_roles where person_id = '10000000-0000-0000-0000-0000000004a1') then raise exception 'roles survived'; end if;
  -- the report stays, without profile and without free text; the reporter email stays / la denuncia queda sin perfil ni texto libre
  if (select count(*) from public.reports where profile_id is null and details is null and reporter_email = 'denunciante@example.test') <> 1 then raise exception 'the report of a1 was not scrubbed correctly'; end if;
  -- records that stay: acceptance, moderation (old one unlinked + the erasure one) / lo que queda
  if (select count(*) from public.terms_acceptances where person_id = '10000000-0000-0000-0000-0000000004a1') <> 1 then raise exception 'acceptance history lost'; end if;
  if (select count(*) from public.moderation_events where profile_id is null and reason = 'Revisión previa') <> 1 then raise exception 'old moderation event lost or still linked'; end if;
  if (select count(*) from public.moderation_events me join public.profile_statuses s on s.id = me.profile_status_id
       where s.code = 'erased' and me.profile_id is null and me.actor_person_id = '10000000-0000-0000-0000-0000000004a1' and me.reason = 'erasure requested by the therapist') <> 1 then
    raise exception 'the erasure was not recorded'; end if;
  -- fingerprints: 3, counter 1, expiry about 12 months / huellas
  if (select count(*) from public.erasure_fingerprints) <> 3 or (select max(erasure_count) from public.erasure_fingerprints) <> 1 then raise exception 'fingerprints'; end if;
  if (select min(expires_at - now()) < interval '364 days' or max(expires_at - now()) > interval '367 days' from public.erasure_fingerprints) then raise exception 'expiry is not about 12 months'; end if;
  -- the canary is nowhere in the public tables / la marca no está en ninguna tabla pública
  if pg_temp.canary_rows('canario-a1') <> '' then raise exception 'personal data of a1 survived in: %', pg_temp.canary_rows('canario-a1'); end if;
  if pg_temp.canary_rows('Borrador CANARIO') <> '' then raise exception 'the draft survived'; end if;
  -- other people untouched / el resto intacto
  if (select count(*) from public.profile_contacts where profile_id in ('20000000-0000-0000-0000-0000000004a2', '20000000-0000-0000-0000-0000000004a4')) <> 3
     or (select count(*) from public.contact_reveals) <> 1 or (select count(*) from public.reports where details = 'Denuncia sobre a4') <> 1 then
    raise exception 'erasing a1 touched other people''s data'; end if;
  if exists (select 1 from public.public_profile_cards where profile_id = a1p) then raise exception 'the erased profile is still public'; end if;
end $$;

-- 5) THE OLD LOGIN CANNOT ACT / EL ACCESO VIEJO NO PUEDE ACTUAR
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a1","role":"authenticated"}', true);
do $$
begin
  if public.current_person_id() is not null or public.is_admin() then raise exception 'an erased login still maps to a person'; end if;
  if (select count(*) from public.people) <> 0 then raise exception 'an erased login still reads people'; end if;
end $$;
reset role;
reset session authorization;

-- 6) A PERSON WITHOUT PROFILE, and a SECOND erasure sharing a phone / PERSONA SIN PERFIL y SEGUNDA eliminación con un teléfono compartido
set session authorization authenticator;
set role service_role;
do $$
declare r record;
begin
  select * into r from public.erase_therapist('10000000-0000-0000-0000-0000000004a3', current_setting('test.fp_a3')::jsonb, 'admin');
  if r.auth_user_id is distinct from '00000000-0000-0000-0000-0000000004a3'::uuid or r.profile_id is not null or r.photo_path is not null then raise exception 'person without profile: %', r; end if;
  select * into r from public.erase_therapist('10000000-0000-0000-0000-0000000004a2', current_setting('test.fp_a2')::jsonb, 'admin');
  if r.profile_id is null then raise exception 'a2 had a profile'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  -- a1 and a2 share the phone hash: counter 2; the rest 1 / a1 y a2 comparten el teléfono: contador 2
  if (select erasure_count from public.erasure_fingerprints where fingerprint = current_setting('test.h_a1_phone')) <> 2 then raise exception 'the counter did not add up'; end if;
  if (select count(*) from public.erasure_fingerprints) <> 5 or (select sum(erasure_count) from public.erasure_fingerprints) <> 6 then raise exception 'fingerprints after 3 erasures'; end if;
  if (select count(*) from public.moderation_events me where me.reason = 'erasure requested by an administrator') <> 2 then raise exception 'admin erasures not recorded'; end if;
end $$;

-- 7) CHECK (as the server) / CONSULTA
set session authorization authenticator;
set role service_role;
do $$
declare phone_h text := current_setting('test.h_a1_phone'); mail_h text := current_setting('test.h_a1_email');
begin
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'phone', 'hash', phone_h))) <> 2 then raise exception 'shared phone must count 2'; end if;
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'email', 'hash', mail_h))) <> 1 then raise exception 'a1 email must count 1'; end if;
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'phone', 'hash', phone_h), jsonb_build_object('type', 'phone', 'hash', phone_h),
       jsonb_build_object('type', 'email', 'hash', mail_h))) <> 3 then raise exception 'duplicates must count once, the rest add up'; end if;
  -- the same hash with another type is another fingerprint / el mismo hash con otro tipo es otra huella
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'email', 'hash', phone_h))) <> 0 then raise exception 'type must be part of the match'; end if;
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'email', 'hash', repeat('0', 64)))) <> 0 then raise exception 'unknown fingerprint counted'; end if;
end $$;
reset role;
reset session authorization;

-- 8) EXPIRY and PURGE / VENCIMIENTO y PURGA
update public.erasure_fingerprints set expires_at = now() - interval '1 day', last_erased_at = now() - interval '2 days', first_erased_at = now() - interval '2 days'
  where fingerprint = current_setting('test.h_a1_email');
set session authorization authenticator;
set role service_role;
do $$
declare mail_h text := current_setting('test.h_a1_email'); removed int;
begin
  if public.check_erasure_fingerprints(jsonb_build_array(jsonb_build_object('type', 'email', 'hash', mail_h))) <> 0 then raise exception 'an expired fingerprint still counts'; end if;
  removed := public.purge_expired_erasure_fingerprints();
  if removed <> 1 then raise exception 'purge should remove 1 expired fingerprint, removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.erasure_fingerprints) <> 4 then raise exception 'purge removed live fingerprints'; end if;
  begin update public.app_settings set value = '0' where key = 'retention_erasure_fingerprints_months'; raise exception 'retention 0 accepted'; exception when check_violation then null; end;
  begin update public.app_settings set value = '"doce"' where key = 'retention_erasure_fingerprints_months'; raise exception 'retention text accepted'; exception when check_violation then null; end;
end $$;
-- an expired but unpurged row restarts instead of adding up / una fila vencida sin purgar reinicia en vez de sumar
update public.erasure_fingerprints set expires_at = now() - interval '1 day', last_erased_at = now() - interval '2 days', first_erased_at = now() - interval '2 days'
  where fingerprint = current_setting('test.h_a1_phone');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000004b6', 'b6@example.test');
insert into public.people (id, auth_user_id, full_name, email) values ('10000000-0000-0000-0000-0000000004b6', '00000000-0000-0000-0000-0000000004b6', 'Persona B6', 'b6@example.test');
set session authorization authenticator;
set role service_role;
select * from public.erase_therapist('10000000-0000-0000-0000-0000000004b6', jsonb_build_array(jsonb_build_object('type', 'phone', 'hash', current_setting('test.h_a1_phone'))), 'self');
reset role;
reset session authorization;
do $$
begin
  if (select erasure_count from public.erasure_fingerprints where fingerprint = current_setting('test.h_a1_phone')) <> 1 then raise exception 'an expired fingerprint must restart at 1, not add up'; end if;
  if (select expires_at <= now() from public.erasure_fingerprints where fingerprint = current_setting('test.h_a1_phone')) then raise exception 'a renewed fingerprint must expire in the future'; end if;
end $$;

rollback;
select 'OK 16-erasure' as result;
