-- Contact reveal: only published profiles, only private contacts, daily counter, no leaks to other roles.
-- Revelado de contacto: solo perfiles publicados, solo contactos privados, contador diario, sin fugas a otros roles.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000002' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2','a3','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000002' || k)::uuid, ('00000000-0000-0000-0000-0000000002' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2','a3','ad']) k;
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000002ad'::uuid, id from public.roles where code = 'admin';

-- a1 published (phone+whatsapp, email, website) | a2 published (phone only) | a3 paused (phone)
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select ('20000000-0000-0000-0000-0000000002' || k)::uuid, ('10000000-0000-0000-0000-0000000002' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '10 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1), 'Perfil ' || k
  from unnest(array['a1','a2','a3']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select ('20000000-0000-0000-0000-0000000002' || x.k)::uuid, ct.id, x.v, x.w
  from (values ('a1','phone','+54 351 555 0001',true), ('a1','email','canary-a1@example.test',false), ('a1','website','https://example.test/a1',false),
               ('a2','phone','+54 351 555 0002',false), ('a3','phone','+54 351 555 0003',false)) x(k, t, v, w)
  join public.contact_types ct on ct.code = x.t;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000002a1', '20000000-0000-0000-0000-0000000002a2', '20000000-0000-0000-0000-0000000002a3');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused'), status_reason = 'test'
  where id = '20000000-0000-0000-0000-0000000002a3';

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.contact_reveals'::regclass) then raise exception 'contact_reveals has no RLS'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contact_reveals'
              and column_name ~* '(ip|user|person|email|session|agent|device|phone|contact_type)') then
    raise exception 'contact_reveals must carry no personal or identifying column';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.reveal_contact(uuid)'::regprocedure) then raise exception 'reveal_contact must be SECURITY DEFINER'; end if;
  if not has_function_privilege('anon', 'public.reveal_contact(uuid)', 'execute') then raise exception 'anon must execute reveal_contact'; end if;
  if has_function_privilege('authenticated', 'public.reveal_contact(uuid)', 'execute')
     or has_function_privilege('service_role', 'public.reveal_contact(uuid)', 'execute') then
    raise exception 'only anon may execute reveal_contact';
  end if;
  if has_function_privilege('anon', 'public.purge_expired_contact_reveals()', 'execute')
     or has_function_privilege('authenticated', 'public.purge_expired_contact_reveals()', 'execute')
     or not has_function_privilege('service_role', 'public.purge_expired_contact_reveals()', 'execute') then
    raise exception 'purge_expired_contact_reveals must be executable by service_role only';
  end if;
  if (select count(*) from public.contact_types where is_private and is_active) < 2 then raise exception 'phone and email must be private contact types'; end if;
  if exists (select 1 from public.contact_types where code = 'website' and is_private) then raise exception 'website must not be private'; end if;
end $$;

-- 2) AS ANON / COMO ANON
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare got text; n int;
begin
  select string_agg(contact_type || '=' || value || '/' || accepts_whatsapp, ',' order by contact_type) into got
    from public.reveal_contact('20000000-0000-0000-0000-0000000002a1');
  if got <> 'email=canary-a1@example.test/false,phone=+54 351 555 0001/true' then raise exception 'reveal a1: %', got; end if;
  -- website never comes out here (it is already public in the view) / la web no sale por acá
  select string_agg(contact_type || '=' || value || '/' || accepts_whatsapp, ',' order by contact_type) into got
    from public.reveal_contact('20000000-0000-0000-0000-0000000002a2');
  if got <> 'phone=+54 351 555 0002/false' then raise exception 'reveal a2: %', got; end if;
  -- paused, unknown and null: no rows / pausado, inexistente y nulo: sin filas
  select count(*) into n from public.reveal_contact('20000000-0000-0000-0000-0000000002a3'); if n <> 0 then raise exception 'paused profile revealed'; end if;
  select count(*) into n from public.reveal_contact('99999999-9999-9999-9999-999999999999'); if n <> 0 then raise exception 'unknown profile revealed'; end if;
  select count(*) into n from public.reveal_contact(null); if n <> 0 then raise exception 'null profile revealed'; end if;
  perform * from public.reveal_contact('20000000-0000-0000-0000-0000000002a1');  -- a1 second time / a1 segunda vez
  -- no direct access to private contacts or to the counters / sin acceso directo
  select count(*) into n from public.profile_contacts where profile_id = '20000000-0000-0000-0000-0000000002a1';
  if n <> 1 then raise exception 'anon sees % contacts of a1 directly (only the website expected)', n; end if;
  begin perform 1 from public.contact_reveals; raise exception 'anon read contact_reveals';
  exception when insufficient_privilege then null; end;
  begin insert into public.contact_reveals (profile_id, day) values ('20000000-0000-0000-0000-0000000002a1', current_date); raise exception 'anon wrote contact_reveals';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_contact_reveals(); raise exception 'anon ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 3) COUNTERS (as owner): a1 twice, a2 once, nothing for paused/unknown / CONTADORES
do $$
declare c1 int; c2 int; n int;
begin
  select reveals_count into c1 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000002a1';
  select reveals_count into c2 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000002a2';
  select count(*) into n from public.contact_reveals;
  if c1 <> 2 or c2 <> 1 or n <> 2 then raise exception 'counters: a1 %, a2 %, rows %', c1, c2, n; end if;
  if exists (select 1 from public.contact_reveals where day <> (now() at time zone 'utc')::date) then raise exception 'day must be today (UTC)'; end if;
end $$;

-- 3b) DEACTIVATED CONTACT TYPES and ORDER / TIPOS DE CONTACTO DESACTIVADOS y ORDEN
do $$
begin
  if (select array_agg(contact_type) from (select * from public.reveal_contact('20000000-0000-0000-0000-0000000002a1')) s) <> array['email', 'phone'] then
    raise exception 'order of the revealed contacts must be email, phone';
  end if;
  -- that owner call counted too: a1 = 3 / esa llamada de dueño también contó: a1 = 3
  update public.contact_reveals set reveals_count = 2 where profile_id = '20000000-0000-0000-0000-0000000002a1';
  update public.contact_types set is_active = false where code = 'email';
end $$;
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select string_agg(contact_type, ',') from public.reveal_contact('20000000-0000-0000-0000-0000000002a1')) <> 'phone' then
    raise exception 'a deactivated contact type was revealed';
  end if;
end $$;
reset role;
reset session authorization;
update public.contact_types set is_active = false where code = 'phone';
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if exists (select 1 from public.reveal_contact('20000000-0000-0000-0000-0000000002a2')) then raise exception 'revealed with every private type deactivated'; end if;
end $$;
reset role;
reset session authorization;
do $$
declare c1 int; c2 int;
begin
  select reveals_count into c1 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000002a1' and day = (now() at time zone 'utc')::date;
  select reveals_count into c2 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000002a2' and day = (now() at time zone 'utc')::date;
  if c1 <> 3 or c2 <> 1 then raise exception 'counters after deactivation: a1 %, a2 % (a1 3 expected: 2 + one phone-only reveal; a2 1: nothing revealed)', c1, c2; end if;
  update public.contact_types set is_active = true where code in ('email', 'phone');
end $$;

-- 4) AUTHENTICATED: therapist cannot reveal nor read counters; admin reads / AUTHENTICATED
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000002a1","role":"authenticated"}', true);
do $$
begin
  begin perform * from public.reveal_contact('20000000-0000-0000-0000-0000000002a2'); raise exception 'authenticated ran reveal_contact';
  exception when insufficient_privilege then null; end;
  if (select count(*) from public.contact_reveals) <> 0 then raise exception 'a therapist sees the counters'; end if;
  begin insert into public.contact_reveals (profile_id, day) values ('20000000-0000-0000-0000-0000000002a1', current_date); raise exception 'authenticated wrote counters';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_contact_reveals(); raise exception 'authenticated ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000002ad","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.contact_reveals) <> 2 then raise exception 'the admin cannot read the counters'; end if;
  begin update public.contact_reveals set reveals_count = 5; if found then raise exception 'admin updated counters through the API'; end if;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 5) RETENTION and CASCADE / RETENCIÓN y CASCADA
insert into public.contact_reveals (profile_id, day) values
  ('20000000-0000-0000-0000-0000000002a2', (now() at time zone 'utc')::date - 400),
  ('20000000-0000-0000-0000-0000000002a3', (now() at time zone 'utc')::date - 360);
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_contact_reveals();
  if removed <> 1 then raise exception 'purge should remove 1 row, removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if (select count(*) from public.contact_reveals) <> 3 then raise exception 'purge removed the wrong rows'; end if;
  begin update public.app_settings set value = '0' where key = 'retention_contact_reveals_months'; raise exception 'retention 0 accepted';
  exception when check_violation then null; end;
  begin update public.app_settings set value = '"doce"' where key = 'retention_contact_reveals_months'; raise exception 'retention text accepted';
  exception when check_violation then null; end;
  if (select is_public from public.app_settings where key = 'retention_contact_reveals_months') then raise exception 'retention setting must be private'; end if;
  -- deleting a profile removes its counters (erasure leaves no residue) / borrar un perfil borra sus contadores
  delete from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000002a2';
  if exists (select 1 from public.contact_reveals where profile_id = '20000000-0000-0000-0000-0000000002a2') then raise exception 'counters survived the profile'; end if;
end $$;

rollback;
select 'OK 14-reveal-contact' as result;
