-- Profile texts: "about" (Sobre mí) and the short description per therapy. They travel only inside a moderated revision,
-- accept no contact data, are public only for published profiles, and "about" stays out of the search card.
-- Textos del perfil: "Sobre mí" y la descripción corta por terapia. Viajan solo en una revisión moderada, no aceptan
-- datos de contacto, son públicos solo en perfiles publicados, y "Sobre mí" no aparece en la tarjeta de búsqueda.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@example.test', now()),  -- therapist, published
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test', now()),  -- therapist, unpublished
  ('00000000-0000-0000-0000-0000000000d4', 'd@example.test', now());  -- admin
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Ana Pérez', 'a@example.test'),
  ('10000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2', 'Beto Gómez', 'b@example.test'),
  ('10000000-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000000d4', 'Admin D', 'd@example.test');
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000d4'::uuid, id from public.roles where code = 'admin';

insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id)
  select ('20000000-0000-0000-0000-0000000000' || k)::uuid, ('10000000-0000-0000-0000-0000000000' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '30 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1)
  from unnest(array['a1', 'b2']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000000' || k)::uuid, (select id from public.contact_types where code = 'phone'), '+54 351 555 0' || n
  from unnest(array['a1', 'b2'], array['102', '103']) as u(k, n);
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id = '20000000-0000-0000-0000-0000000000a1';

-- helpers / ayudas
create function pg_temp.open_revision(p_id uuid, p_profile text, p_payload jsonb) returns void language sql as $$
  insert into public.profile_revisions (id, profile_id, status_id, payload, submitted_at, due_at)
  values (p_id, ('20000000-0000-0000-0000-0000000000' || p_profile)::uuid,
          (select id from public.revision_statuses where code = 'draft'), p_payload, null, null);
$$;
-- a payload with one therapy that carries a description / un payload con una terapia con descripción
create function pg_temp.therapy_payload(p_about jsonb, p_description jsonb) returns jsonb language sql as $$
  select jsonb_build_object('about', p_about, 'therapies', jsonb_build_array(jsonb_build_object(
    'therapy_id', (select min(id) from public.therapies where is_active),
    'service_modes', jsonb_build_array((select min(id) from public.service_modes where is_active)),
    'session_formats', jsonb_build_array((select min(id) from public.session_formats where is_active)),
    'description', p_description)))
$$;

-- 1) Direct writes are closed (the CHECKs, and the API roles have no write grant) / escrituras directas cerradas
do $$
declare ok boolean;
begin
  update public.therapist_profiles set about = 'Presentación válida.' where id = '20000000-0000-0000-0000-0000000000b2';
  ok := false; begin update public.therapist_profiles set about = '' where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an empty about was accepted'; end if;
  ok := false; begin update public.therapist_profiles set about = ' con espacios ' where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an about with spaces around was accepted'; end if;
  ok := false; begin update public.therapist_profiles set about = repeat('x', 1501) where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an about of 1501 characters was accepted'; end if;
  update public.therapist_profiles set about = repeat('x', 1500) where id = '20000000-0000-0000-0000-0000000000b2';
  ok := false; begin update public.therapist_profiles set about = 'Escribime a https://mi-sitio.com' where id = '20000000-0000-0000-0000-0000000000b2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an about with a link was accepted'; end if;
  update public.therapist_profiles set about = 'Presentación válida de Beto.' where id = '20000000-0000-0000-0000-0000000000b2';
end
$$;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare denied boolean;
begin
  denied := false; begin update public.therapist_profiles set about = 'Escrito directo'; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'a therapist wrote about directly'; end if;
  denied := false; begin update public.profile_therapies set description = 'Escrito directo'; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'a therapist wrote a therapy description directly'; end if;
  -- nobody sees another therapist''s unpublished about / nadie ve el "Sobre mí" de un perfil no publicado ajeno
  if exists (select 1 from public.therapist_profiles where about = 'Presentación válida de Beto.') then
    raise exception 'a therapist can read the about of another profile';
  end if;
end
$$;
reset role;
reset session authorization;

-- 2) Submit: invalid texts are refused at once (22023) / el envío rechaza de entrada los textos inválidos
create function pg_temp.submit_bad(p_label text, p_payload jsonb) returns void language plpgsql as $$
declare ok boolean := false;
begin
  update public.profile_revisions set payload = p_payload, status_id = (select id from public.revision_statuses where code = 'draft'),
    submitted_at = null, due_at = null where id = '30000000-0000-0000-0000-0000000000a2';
  begin
    set local role authenticated;
    perform public.submit_revision('30000000-0000-0000-0000-0000000000a2');
  exception when sqlstate '22023' then ok := true; end;
  reset role;
  if not ok then raise exception 'case [%] was accepted at submit', p_label; end if;
end $$;
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a2', 'a1', '{"about":"x"}');
set session authorization authenticator;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
reset session authorization;
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  perform pg_temp.submit_bad('about with a link', '{"about":"Mirá mi web www.mi-sitio.com.ar"}');
  perform pg_temp.submit_bad('about with an e-mail', '{"about":"Escribime a ana@mail.com"}');
  perform pg_temp.submit_bad('about with a handle', '{"about":"Seguime en @ana_reiki"}');
  perform pg_temp.submit_bad('about with a phone', '{"about":"Llamame al 299 412-3456"}');
  perform pg_temp.submit_bad('about too long', jsonb_build_object('about', repeat('y', 1501)));
  perform pg_temp.submit_bad('about as number', '{"about":5}');
  perform pg_temp.submit_bad('description with a link', pg_temp.therapy_payload('"ok"', '"Más en https://x.com"'));
  perform pg_temp.submit_bad('description too long', pg_temp.therapy_payload('"ok"', to_jsonb(repeat('z', 201))));
  perform pg_temp.submit_bad('description as number', pg_temp.therapy_payload('"ok"', '5'));
end
$$;

-- 3) Approval is all-or-nothing as well (a bad payload that skipped the submit) / la aprobación también es todo o nada
create function pg_temp.approve_bad(p_label text, p_payload jsonb) returns void language plpgsql as $$
declare ok boolean := false;
begin
  update public.profile_revisions set payload = p_payload, status_id = (select id from public.revision_statuses where code = 'pending_review'),
    closed_at = null, decided_at = null, submitted_at = now(), due_at = now() + interval '3 days'
    where id = '30000000-0000-0000-0000-0000000000a2';
  begin
    set local role authenticated;
    perform public.approve_revision('30000000-0000-0000-0000-0000000000a2');
  exception when sqlstate '22023' then ok := true; end;
  reset role;
  if not ok then raise exception 'case [%] was approved', p_label; end if;
  if (select about from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') is not null then
    raise exception 'case [%] left a partial change', p_label;
  end if;
end $$;
do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
  perform pg_temp.approve_bad('about with a link', '{"about":"Mirá https://x.com"}');
  perform pg_temp.approve_bad('description with an e-mail', pg_temp.therapy_payload('"Texto válido"', '"escribime a ana@mail.com"'));
end
$$;
delete from public.profile_revisions where id = '30000000-0000-0000-0000-0000000000a2';

-- 4) The happy path: submit (flagged words are noted, never block), approve, apply / camino feliz
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a3', 'a1',
  pg_temp.therapy_payload('"Hace años acompaño personas con la curación del alma. Atiendo a distancia."', '"Método LNT, formación en Barcelona."'));
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare flagged text[];
begin
  flagged := public.submit_revision('30000000-0000-0000-0000-0000000000a3');
  if not ('curacion' = any (flagged)) then raise exception 'the about text must be checked against restricted terms: %', flagged; end if;
end
$$;
reset role;
reset session authorization;
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000000a3');
reset role;
reset session authorization;
do $$
begin
  if (select about from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') <> 'Hace años acompaño personas con la curación del alma. Atiendo a distancia.' then
    raise exception 'the approved about was not applied';
  end if;
  if (select description from public.profile_therapies where profile_id = '20000000-0000-0000-0000-0000000000a1') <> 'Método LNT, formación en Barcelona.' then
    raise exception 'the approved therapy description was not applied';
  end if;
end
$$;

-- 5) Visitors (anon): the published profile shows both texts in the detail view; the card has no "about";
--    the unpublished profile shows nothing / visitantes: el perfil publicado muestra los dos textos en el detalle;
--    la tarjeta no trae "about"; el no publicado no muestra nada
do $$
begin
  if exists (select 1 from pg_attribute where attrelid = 'public.public_profile_cards'::regclass and attname = 'about' and not attisdropped) then
    raise exception 'the search card must not carry about';
  end if;
end
$$;
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare denied boolean;
begin
  if (select about from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000a1') is distinct from
     'Hace años acompaño personas con la curación del alma. Atiendo a distancia.' then
    raise exception 'anon does not see the about of a published profile';
  end if;
  if (select therapies_detail -> 0 ->> 'description' from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000a1')
     is distinct from 'Método LNT, formación en Barcelona.' then
    raise exception 'anon does not see the therapy description of a published profile';
  end if;
  if exists (select 1 from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000b2') then
    raise exception 'anon sees an unpublished profile';
  end if;
  -- on the base tables only published rows, and nothing is writable / en las tablas base solo filas publicadas
  if (select count(*) from public.therapist_profiles where about is not null) <> 1 then
    raise exception 'anon must read the about of published profiles only';
  end if;
  denied := false; begin update public.therapist_profiles set about = 'Hackeado'; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon wrote about'; end if;
  denied := false; begin update public.profile_therapies set description = 'Hackeado'; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon wrote a therapy description'; end if;
  denied := false; begin perform public.validate_profile_texts('{}'::jsonb); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon can run validate_profile_texts'; end if;
  denied := false; begin perform public.contains_contact_data('x'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon can run contains_contact_data'; end if;
end
$$;
reset role;
reset session authorization;

-- 6) A later revision can clear both texts (null or empty text) / una revisión posterior puede borrar los dos textos
select pg_temp.open_revision('30000000-0000-0000-0000-0000000000a4', 'a1', pg_temp.therapy_payload('null', '"   "'));
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select public.submit_revision('30000000-0000-0000-0000-0000000000a4');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
set role authenticated;
select public.approve_revision('30000000-0000-0000-0000-0000000000a4');
reset role;
reset session authorization;
do $$
begin
  if (select about from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000000a1') is not null then raise exception 'about was not cleared'; end if;
  if (select description from public.profile_therapies where profile_id = '20000000-0000-0000-0000-0000000000a1') is not null then raise exception 'the description was not cleared'; end if;
end
$$;

rollback;
\echo 'OK: profile texts travel in moderated revisions, accept no contact data and are public only when published / los textos del perfil viajan en revisiones moderadas, no aceptan datos de contacto y son públicos solo si el perfil está publicado'
