-- Public views: what a visitor (anon) can and cannot see. Phone, email and legal name never leak; unpublished stays hidden.
-- Vistas públicas: qué ve y qué no ve un visitante (anon). Teléfono, mail y nombre legal nunca se filtran; lo no publicado sigue oculto.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000000' || k)::uuid, k || '@example.test', now() from unnest(array['a1','b2','c3','d4','e5','f6']) k;
-- legal names carry a canary: if one shows up in a view, the test fails / el nombre legal lleva una marca
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000000' || k)::uuid, ('00000000-0000-0000-0000-0000000000' || k)::uuid,
         'Nombre Legal Canario ' || k, 'canary-' || k || '@example.test'
  from unnest(array['a1','b2','c3','d4','e5','f6']) k;
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000d4'::uuid, id from public.roles where code = 'admin';

-- Profiles: a1 published (rich), b2 unpublished (rich), c3 paused, e5 suspended, f6 published (minimal)
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name, headline, zone, practice_start_year, photo_path)
  select ('20000000-0000-0000-0000-0000000000' || x.k)::uuid, ('10000000-0000-0000-0000-0000000000' || x.k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '10 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id
            join public.locations r on r.id = l.parent_id join public.locations c on c.id = r.parent_id
           where ll.code = 'city' order by l.id limit 1),
         x.name, 'Titular de ' || x.k, 'Zona ' || x.k, 2015, x.k || '/photo.png'
  from (values ('a1', 'Ana Pública'), ('b2', 'Beto Oculto'), ('c3', 'Carla Pausada'), ('e5', 'Eli Suspendida'), ('f6', 'Flor Mínima')) x(k, name);

create function pg_temp.fill(p_profile uuid, p_k text, p_rich boolean) returns void language plpgsql as $$
declare t1 int := (select id from public.therapies where is_active order by id limit 1);
        t2 int := (select id from public.therapies where is_active order by id limit 1 offset 1);
begin
  insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
    values (p_profile, (select id from public.contact_types where code = 'phone'), '+54 351 555 77' || regexp_replace(p_k, '[^0-9]', '', 'g'), true);
  if not p_rich then return; end if;
  insert into public.profile_contacts (profile_id, contact_type_id, value)
    values (p_profile, (select id from public.contact_types where code = 'email'), 'canary-mail-' || p_k || '@example.test'),
           (p_profile, (select id from public.contact_types where code = 'website'), 'https://example.test/' || p_k);
  insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values (p_profile, t1, 60), (p_profile, t2, 45);
  insert into public.profile_languages (profile_id, language_id) select p_profile, id from public.languages where code in ('es', 'en');
  insert into public.profile_service_modes (profile_id, service_mode_id) select p_profile, id from public.service_modes;
  insert into public.profile_session_formats (profile_id, session_format_id) select p_profile, id from public.session_formats where code = 'individual';
  insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id) values
    (p_profile, t1, (select id from public.rate_audiences where code = 'own_country'), 9000, (select id from public.currencies where code = 'ARS')),
    (p_profile, t2, (select id from public.rate_audiences where code = 'own_country'), 12000, (select id from public.currencies where code = 'ARS')),
    (p_profile, t1, (select id from public.rate_audiences where code = 'other_countries'), 30, (select id from public.currencies where code = 'USD'));
end $$;
select pg_temp.fill('20000000-0000-0000-0000-0000000000a1', 'a1', true), pg_temp.fill('20000000-0000-0000-0000-0000000000b2', 'b2', true),
       pg_temp.fill('20000000-0000-0000-0000-0000000000c3', 'c3', true), pg_temp.fill('20000000-0000-0000-0000-0000000000e5', 'e5', true),
       pg_temp.fill('20000000-0000-0000-0000-0000000000f6', 'f6', false);
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id in ('20000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-0000000000f6');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused'), status_reason = 'canary-reason-paused' where id = '20000000-0000-0000-0000-0000000000c3';
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'suspended'), status_reason = 'canary-reason-suspended' where id = '20000000-0000-0000-0000-0000000000e5';
update public.therapist_profiles set status_reason = 'canary-reason-leftover' where id = '20000000-0000-0000-0000-0000000000a1';

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare v record; cols text;
begin
  for v in select c.relname, c.reloptions from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm') loop
    if v.reloptions is null or not ('security_invoker=true' = any (v.reloptions)) then
      raise exception 'the view % is not security_invoker', v.relname;
    end if;
  end loop;
  select string_agg(column_name, ',' order by ordinal_position) into cols from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profile_cards';
  if cols <> 'profile_id,display_name,photo_path,headline,zone,approved_at,city_id,city_name,region_id,region_name,country_id,country_name,country_iso,therapy_ids,therapy_names,service_modes,session_formats,languages,rates_from,rates_confirmed_at,rates_current,is_pinned' then
    raise exception 'the columns of public_profile_cards changed: %', cols;
  end if;
  select string_agg(column_name, ',' order by ordinal_position) into cols from information_schema.columns
    where table_schema = 'public' and table_name = 'public_profile_detail';
  if cols <> 'profile_id,display_name,photo_path,headline,zone,approved_at,city_id,city_name,region_id,region_name,country_id,country_name,country_iso,therapy_ids,therapy_names,service_modes,session_formats,languages,rates_from,rates_confirmed_at,rates_current,is_pinned,practice_start_year,website,therapies_detail,instagram,facebook,tiktok,youtube' then
    raise exception 'the columns of public_profile_detail changed: %', cols;
  end if;
end
$$;

-- THE WRITTEN LIST of what anon can read / LA LISTA ESCRITA de lo que lee anon (exact: nothing more, nothing less)
do $$
declare got text[]; expected text[];
begin
  select array_agg(table_name || '.' || column_name || ':' || privilege_type order by table_name, column_name) into got
    from information_schema.role_column_grants where grantee = 'anon' and table_schema = 'public';
  expected := array[
    'profile_contacts.contact_type_id:SELECT', 'profile_contacts.profile_id:SELECT', 'profile_contacts.value:SELECT',
    'profile_languages.language_id:SELECT', 'profile_languages.profile_id:SELECT',
    'profile_service_modes.profile_id:SELECT', 'profile_service_modes.service_mode_id:SELECT',
    'profile_session_formats.profile_id:SELECT', 'profile_session_formats.session_format_id:SELECT',
    'profile_therapies.profile_id:SELECT', 'profile_therapies.session_minutes:SELECT', 'profile_therapies.therapy_id:SELECT',
    'profile_therapy_rates.amount:SELECT', 'profile_therapy_rates.currency_id:SELECT', 'profile_therapy_rates.profile_id:SELECT',
    'profile_therapy_rates.rate_audience_id:SELECT', 'profile_therapy_rates.therapy_id:SELECT',
    'therapist_profiles.approved_at:SELECT', 'therapist_profiles.display_name:SELECT', 'therapist_profiles.headline:SELECT',
    'therapist_profiles.id:SELECT', 'therapist_profiles.is_pinned:SELECT', 'therapist_profiles.location_id:SELECT',
    'therapist_profiles.photo_path:SELECT', 'therapist_profiles.practice_start_year:SELECT',
    'therapist_profiles.rates_confirmed_at:SELECT', 'therapist_profiles.zone:SELECT'];
  -- column grants that belong to table-level grants (the catalogs and views) are listed by the table-level view of the standard
  got := array(select g from unnest(got) g where split_part(g, '.', 1) = any (array['profile_contacts', 'profile_languages', 'profile_service_modes',
    'profile_session_formats', 'profile_therapies', 'profile_therapy_rates', 'therapist_profiles']));
  if got is distinct from expected then
    raise exception 'anon column grants differ from the written list: %', (select array_agg(x) from (select unnest(got) except select unnest(expected) union all select unnest(expected) except select unnest(got)) q(x));
  end if;
  -- table level: the 10 catalogs and the 2 views, SELECT only
  select array_agg(table_name order by table_name) into got from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public' and privilege_type = 'SELECT';
  if got is distinct from array['currencies', 'languages', 'location_levels', 'location_translations', 'locations', 'public_profile_cards', 'public_profile_detail',
                                'rate_audiences', 'service_modes', 'session_formats', 'therapies', 'therapy_translations'] then
    raise exception 'anon table grants differ from the written list: %', got;
  end if;
  if exists (select 1 from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public' and privilege_type <> 'SELECT') then
    raise exception 'anon has a non-SELECT table privilege';
  end if;
end
$$;

-- helper function permissions / permisos de las funciones auxiliares
do $$
declare f text;
begin
  foreach f in array array['public.is_published_profile(uuid)', 'public.public_contact_code(smallint)'] loop
    if not has_function_privilege('anon', f, 'EXECUTE') or not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'anon/authenticated cannot execute %', f; end if;
    if has_function_privilege('service_role', f, 'EXECUTE') then raise exception 'service_role can execute %', f; end if;
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

-- the visitor cannot read contact_types, so the ids are passed through settings / el visitante no lee contact_types
select set_config('test.phone_id', (select id::text from public.contact_types where code = 'phone'), true),
       set_config('test.email_id', (select id::text from public.contact_types where code = 'email'), true),
       set_config('test.website_id', (select id::text from public.contact_types where code = 'website'), true);

-- 2) THE VISITOR / EL VISITANTE
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare
  c public.public_profile_cards%rowtype;
  d public.public_profile_detail%rowtype;
  txt text; pat text;
  t1 int := (select id from public.therapies where is_active order by id limit 1);
begin
  -- only published profiles / solo perfiles publicados
  if (select count(*) from public.public_profile_cards) <> 2 or (select count(*) from public.public_profile_detail) <> 2 then
    raise exception 'anon must see exactly the 2 published profiles';
  end if;
  if exists (select 1 from public.public_profile_cards where profile_id in ('20000000-0000-0000-0000-0000000000b2', '20000000-0000-0000-0000-0000000000c3', '20000000-0000-0000-0000-0000000000e5')) then
    raise exception 'an unpublished, paused or suspended profile is visible';
  end if;

  select * into c from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if c.display_name <> 'Ana Pública' then raise exception 'the card must show the public name, not the legal one: %', c.display_name; end if;
  if c.headline <> 'Titular de a1' or c.zone <> 'Zona a1' or c.photo_path <> 'a1/photo.png' or c.approved_at is null then raise exception 'card fields wrong'; end if;
  if c.city_name is null or c.region_name is null or c.country_name is null or c.country_iso !~ '^[A-Z]{2}$'
     or c.city_id is null or c.region_id is null or c.country_id is null then raise exception 'location names or ids missing on the card'; end if;
  if array_length(c.therapy_ids, 1) <> 2 or array_length(c.therapy_names, 1) <> 2 or c.therapy_names[1] is null then raise exception 'therapies wrong on the card'; end if;
  if c.service_modes <> array['in_person', 'remote'] or c.session_formats <> array['individual'] or c.languages <> array['es', 'en'] then
    raise exception 'modes, formats or languages wrong: % % %', c.service_modes, c.session_formats, c.languages;
  end if;
  if c.rates_from -> 'own_country' ->> 'currency' <> 'ARS' or (c.rates_from -> 'own_country' ->> 'amount')::numeric <> 9000
     or c.rates_from -> 'other_countries' ->> 'currency' <> 'USD' or (c.rates_from -> 'other_countries' ->> 'amount')::numeric <> 30 then
    raise exception 'the "from" rates are wrong: %', c.rates_from;
  end if;

  -- the minimal profile / el perfil mínimo
  select * into c from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000000f6';
  if c.therapy_ids <> '{}' or c.service_modes <> '{}' or c.languages <> '{}' or c.rates_from <> '{}'::jsonb then raise exception 'a minimal profile must show empty lists'; end if;

  -- the detail / el detalle
  select * into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if d.website <> 'https://example.test/a1' or d.practice_start_year <> 2015 then raise exception 'website or start year wrong in the detail'; end if;
  if jsonb_array_length(d.therapies_detail) <> 2 or (d.therapies_detail -> 0 ->> 'session_minutes')::int <> 60
     or jsonb_array_length(d.therapies_detail -> 0 -> 'rates') <> 2 or d.therapies_detail -> 0 -> 'rates' -> 0 ->> 'audience' <> 'own_country' then
    raise exception 'therapies_detail wrong: %', d.therapies_detail;
  end if;
  if (select website from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000f6') is not null then raise exception 'a profile without website must show none'; end if;

  -- LEAK CANARIES: nothing private appears anywhere in any row of either view / nada privado aparece en ninguna fila
  for txt in select row_to_json(x)::text from public.public_profile_cards x union all select row_to_json(y)::text from public.public_profile_detail y loop
    foreach pat in array array['555 77', 'canary', 'Nombre Legal', '@', 'reason', 'person_id'] loop
      if position(pat in txt) > 0 then raise exception 'LEAK: "%" found in a public view row: %', pat, txt; end if;
    end loop;
  end loop;
end
$$;

-- base tables as anon: only the listed columns, only published rows / tablas base como anon
do $$
declare stmt text; denied boolean;
begin
  if (select count(*) from public.therapist_profiles) <> 2 then raise exception 'anon must see 2 published profile rows'; end if;
  if (select count(approved_at) from public.therapist_profiles) <> 2 then raise exception 'anon must read approved_at of published profiles'; end if;
  foreach stmt in array array[
    $q$select * from public.therapist_profiles$q$, $q$select person_id from public.therapist_profiles$q$,
    $q$select status_id from public.therapist_profiles$q$, $q$select status_reason from public.therapist_profiles$q$,
    $q$select created_at from public.therapist_profiles$q$,
    $q$select * from public.profile_contacts$q$, $q$select accepts_whatsapp from public.profile_contacts$q$,
    $q$select 1 from public.people$q$, $q$select 1 from public.person_roles$q$, $q$select 1 from public.profile_revisions$q$,
    $q$select 1 from public.moderation_events$q$, $q$select 1 from public.terms_acceptances$q$, $q$select 1 from public.legal_document_types$q$,
    $q$select 1 from public.app_settings$q$, $q$select 1 from public.restricted_terms$q$, $q$select 1 from public.contact_types$q$,
    $q$select 1 from public.profile_statuses$q$, $q$select 1 from public.revision_statuses$q$, $q$select 1 from public.roles$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;

  -- contacts: ONLY the website of published profiles; no phone, no email (the most important check)
  if (select count(*) from public.profile_contacts) <> 1 then raise exception 'anon must see exactly 1 contact row (the website of a1), saw %', (select count(*) from public.profile_contacts); end if;
  if (select value from public.profile_contacts) <> 'https://example.test/a1' then raise exception 'the only public contact must be the website'; end if;
  if exists (select 1 from public.profile_contacts where value like '%555%' or value like '%@%') then raise exception 'a phone or email is readable by anon'; end if;
  if exists (select 1 from public.profile_contacts where profile_id = '20000000-0000-0000-0000-0000000000f6') then raise exception 'the phone of a published profile is readable by anon'; end if;

  -- child tables: rows of published profiles only / hijas: solo filas de perfiles publicados
  if (select count(*) from public.profile_therapies) <> 2 or (select count(*) from public.profile_languages) <> 2
     or (select count(*) from public.profile_service_modes) <> 2 or (select count(*) from public.profile_session_formats) <> 1
     or (select count(*) from public.profile_therapy_rates) <> 3 then
    raise exception 'child tables expose more than the published profile';
  end if;

  -- helper functions / funciones auxiliares
  if not public.is_published_profile('20000000-0000-0000-0000-0000000000a1') or public.is_published_profile('20000000-0000-0000-0000-0000000000b2')
     or public.is_published_profile(gen_random_uuid()) then raise exception 'is_published_profile is wrong'; end if;
  if public.public_contact_code(current_setting('test.phone_id')::smallint) is not null
     or public.public_contact_code(current_setting('test.email_id')::smallint) is not null then raise exception 'phone or email reported as public';
  end if;
  if public.public_contact_code(current_setting('test.website_id')::smallint) <> 'website' then raise exception 'website must be public'; end if;
end
$$;

-- anon cannot write anything it can read / anon no escribe nada de lo que lee
do $$
declare stmt text; denied boolean; t text;
begin
  foreach t in array array['therapist_profiles', 'profile_therapies', 'profile_languages', 'profile_service_modes', 'profile_session_formats', 'profile_therapy_rates', 'profile_contacts'] loop
    foreach stmt in array array[format('delete from public.%I', t), format('update public.%I set profile_id = profile_id', t)] loop
      if t like 'therapist%' and stmt like 'update%' then stmt := 'update public.therapist_profiles set id = id'; end if;
      denied := false;
      begin execute stmt; exception when insufficient_privilege or undefined_column then denied := true; end;
      if not denied then raise exception 'anon could run: %', stmt; end if;
    end loop;
  end loop;
  -- views are not updatable here, so check the privileges themselves / las vistas no son actualizables: se miran los permisos
  foreach t in array array['public_profile_cards', 'public_profile_detail'] loop
    if has_table_privilege('anon', 'public.' || t, 'INSERT') or has_table_privilege('anon', 'public.' || t, 'UPDATE')
       or has_table_privilege('anon', 'public.' || t, 'DELETE') or has_table_privilege('anon', 'public.' || t, 'TRUNCATE') then
      raise exception 'anon can write to the view %', t;
    end if;
  end loop;
  denied := false;
  begin insert into public.profile_contacts (profile_id, contact_type_id, value) values (gen_random_uuid(), 1, 'x'); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon could insert a contact'; end if;
end
$$;
reset role;
reset session authorization;

-- 3) CHANGES show up immediately and nothing stale remains / los cambios se ven al instante
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused') where id = '20000000-0000-0000-0000-0000000000a1';
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.public_profile_cards) <> 1 or (select count(*) from public.profile_contacts) <> 0 or (select count(*) from public.profile_therapies) <> 0 then
    raise exception 'a paused profile must disappear from the views and from the tables';
  end if;
end
$$;
reset role;
reset session authorization;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published') where id = '20000000-0000-0000-0000-0000000000a1';
update public.therapies set is_active = false where id = (select id from public.therapies where is_active order by id limit 1);
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare c public.public_profile_cards%rowtype; d public.public_profile_detail%rowtype;
begin
  select * into c from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if array_length(c.therapy_ids, 1) <> 1 then raise exception 'a deactivated therapy must disappear from the card'; end if;
  if (c.rates_from -> 'own_country' ->> 'amount')::numeric <> 12000 or c.rates_from ? 'other_countries' then
    raise exception 'rates of a deactivated therapy must not count: %', c.rates_from;
  end if;
  select * into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if jsonb_array_length(d.therapies_detail) <> 1 then raise exception 'a deactivated therapy must disappear from the detail'; end if;
end
$$;
reset role;
reset session authorization;
-- logged-in roles CAN read inactive therapies in the catalog, so the views themselves must hide them (not only the catalog policy)
-- los roles con sesión SÍ leen terapias inactivas del catálogo, así que las vistas mismas deben ocultarlas
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$
declare c public.public_profile_cards%rowtype; d public.public_profile_detail%rowtype;
begin
  select * into c from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if array_length(c.therapy_ids, 1) <> 1 then raise exception 'the card must hide a deactivated therapy even for the admin'; end if;
  if (c.rates_from -> 'own_country' ->> 'amount')::numeric <> 12000 or c.rates_from ? 'other_countries' then
    raise exception 'rates of a deactivated therapy must not count even for the admin: %', c.rates_from;
  end if;
  select * into d from public.public_profile_detail where profile_id = '20000000-0000-0000-0000-0000000000a1';
  if jsonb_array_length(d.therapies_detail) <> 1 then raise exception 'the detail must hide a deactivated therapy even for the admin'; end if;
end
$$;
reset role;
reset session authorization;
update public.therapies set is_active = true where not is_active and code = (select code from public.therapies order by id limit 1);

-- 4) LOGGED-IN USERS: the views never show unpublished profiles; public pages use anon / usuarios con sesión
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.public_profile_cards) <> 0 then raise exception 'a therapist with an unpublished profile sees it in the public view'; end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.public_profile_cards) <> 1 then raise exception 'a therapist must see only their own published profile in the view (public pages use anon)'; end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.public_profile_cards) <> 2 then raise exception 'the admin must see the 2 published profiles in the view'; end if;
end $$;
reset role;
reset session authorization;

rollback;
\echo 'OK: visitors see only published profiles, never phone, email or legal name / los visitantes ven solo perfiles publicados, nunca teléfono, mail ni nombre legal'
