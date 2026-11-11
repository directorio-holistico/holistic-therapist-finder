-- Therapist registration and legal acceptances: verified email, required documents, optional consent, evidence, isolation.
-- Alta del terapeuta y aceptaciones legales: mail verificado, documentos obligatorios, consentimiento opcional, evidencia, aislamiento.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000a1', '  Ana@Example.test ', now()),     -- verified, will register
  ('00000000-0000-0000-0000-0000000000b2', 'b@example.test', null),            -- NOT verified
  ('00000000-0000-0000-0000-0000000000c3', 'ana@example.test', now()),         -- same email as A (another login)
  ('00000000-0000-0000-0000-0000000000d4', 'd@example.test', now()),           -- verified, registers with offers consent
  ('00000000-0000-0000-0000-0000000000e5', 'e@example.test', now()),           -- admin
  ('00000000-0000-0000-0000-0000000000f6', 'f@example.test', now());           -- verified, never registers
insert into public.people (id, auth_user_id, full_name, email)
  values ('10000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000e5', 'Admin E', 'e@example.test');
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000000e5'::uuid, id from public.roles where code = 'admin';

-- 1) Table constraints and the evidence trigger (as owner) / Restricciones y trigger de evidencia (dueño)
do $$
declare ok boolean; t smallint := (select id from public.legal_document_types where code = 'offers_consent');
  req smallint := (select id from public.legal_document_types where code = 'terms');
begin
  insert into public.terms_acceptances (id, person_id, document_type_id, version)
    values ('40000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-0000000000e5', t, 'v1'),
           ('40000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-0000000000e5', req, 'v1');
  ok := false;
  begin insert into public.terms_acceptances (person_id, document_type_id, version) values ('10000000-0000-0000-0000-0000000000e5', t, 'v1');
  exception when unique_violation then ok := true; end;
  if not ok then raise exception 'two active acceptances of the same version were accepted'; end if;
  ok := false;
  begin insert into public.terms_acceptances (person_id, document_type_id, version) values ('10000000-0000-0000-0000-0000000000e5', t, 'bad version');
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'an invalid version was accepted'; end if;
  ok := false;
  begin insert into public.terms_acceptances (person_id, document_type_id, version, revoked_at) values ('10000000-0000-0000-0000-0000000000e5', t, 'v9', now());
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'an acceptance born revoked was accepted'; end if;
  -- evidence is immutable, even for the owner / la evidencia es inmutable, incluso para el dueño
  ok := false;
  begin update public.terms_acceptances set version = 'v2' where id = '40000000-0000-0000-0000-0000000000e1'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'the version of an acceptance was edited'; end if;
  ok := false;
  begin update public.terms_acceptances set accepted_at = now() - interval '1 year' where id = '40000000-0000-0000-0000-0000000000e1'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'the acceptance date was edited'; end if;
  ok := false;
  begin update public.terms_acceptances set revoked_at = now() where id = '40000000-0000-0000-0000-0000000000e2'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a required document was revoked'; end if;
  update public.terms_acceptances set revoked_at = now() where id = '40000000-0000-0000-0000-0000000000e1';  -- optional: allowed
  ok := false;
  begin update public.terms_acceptances set revoked_at = null where id = '40000000-0000-0000-0000-0000000000e1'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a revoked acceptance was reactivated'; end if;
  ok := false;
  begin update public.terms_acceptances set revoked_at = now() + interval '1 day' where id = '40000000-0000-0000-0000-0000000000e1'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'the revocation date was changed'; end if;
  -- after revoking, the same version can be accepted again (a new row) / tras retirar, se puede volver a aceptar (fila nueva)
  insert into public.terms_acceptances (person_id, document_type_id, version) values ('10000000-0000-0000-0000-0000000000e5', t, 'v1');
  if (select count(*) from public.legal_document_types where is_required) <> 3 then raise exception 'expected 3 required documents'; end if;
end
$$;

-- 2) Registration of A (email with spaces and capitals; the email comes from the login, never from a parameter)
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  pid uuid;
  ok boolean;
  n_people int := (select count(*) from public.people);
  good constant jsonb := '{"terms":"2026-11","privacy":"2026-11","legal_declaration":"2026-11"}';
begin
  -- every bad call leaves nothing behind (one transaction) / cada llamada mala no deja nada
  ok := false; begin perform public.register_therapist('', good); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an empty name was accepted'; end if;
  ok := false; begin perform public.register_therapist(repeat('x', 121), good); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a 121 character name was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', '{"terms":"2026-11","privacy":"2026-11"}'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'registration without the legal declaration was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', '{}'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'registration without documents was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', '[]'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a non-object acceptances was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', null); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'null acceptances were accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', good || '{"hack":"1"}'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an unknown document was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', '{"terms":"bad version!","privacy":"1","legal_declaration":"1"}'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'an invalid version was accepted'; end if;
  ok := false; begin perform public.register_therapist('Ana', good || '{"offers_consent":5}'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a non-text offers version was accepted'; end if;
  if (select count(*) from public.people) <> n_people then raise exception 'a failed registration left a person behind'; end if;

  pid := public.register_therapist('  Ana Pérez  ', good);
  if pid is null then raise exception 'no profile id returned'; end if;

  -- it cannot be done twice / no se puede dos veces
  ok := false; begin perform public.register_therapist('Ana', good); exception when sqlstate '23505' then ok := true; end;
  if not ok then raise exception 'a second registration was accepted'; end if;
end
$$;
do $$
declare p public.people%rowtype;
begin
  select * into p from public.people where auth_user_id = '00000000-0000-0000-0000-0000000000a1';
  if p.full_name <> 'Ana Pérez' then raise exception 'the name was not trimmed: [%]', p.full_name; end if;
  if p.email <> 'ana@example.test' then raise exception 'the email must come from the login, normalized: [%]', p.email; end if;
  if (select array_agg(r.code order by r.code) from public.person_roles pr join public.roles r on r.id = pr.role_id where pr.person_id = p.id) <> array['therapist'] then
    raise exception 'the person must have exactly the therapist role';
  end if;
  if (select count(*) from public.terms_acceptances where person_id = p.id) <> 3 then raise exception 'expected the 3 required acceptances only (offers unchecked by default)'; end if;
  if (select count(*) from public.therapist_profiles tp join public.profile_statuses ps on ps.id = tp.status_id
        where tp.person_id = p.id and ps.code = 'unpublished' and tp.approved_at is null and tp.location_id is null) <> 1 then
    raise exception 'the profile must be empty and unpublished';
  end if;
  if public.is_admin() then raise exception 'a new therapist must not be admin'; end if;
end
$$;

-- 3) Offers consent: give, withdraw, give again (history is kept) / Consentimiento de ofertas
do $$
declare ok boolean; me uuid := public.current_person_id();
  offers smallint := (select id from public.legal_document_types where code = 'offers_consent');
begin
  ok := false; begin perform public.set_offers_consent(true, null); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'consent without a version was accepted'; end if;
  ok := false; begin perform public.set_offers_consent(null, 'v1'); exception when sqlstate '22023' then ok := true; end;
  if not ok then raise exception 'a null value was accepted'; end if;
  perform public.set_offers_consent(true, 'v1');
  perform public.set_offers_consent(true, 'v1');  -- already active: no duplicate
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = offers) <> 1 then raise exception 'a duplicate consent was created'; end if;
  perform public.set_offers_consent(false);
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = offers and revoked_at is not null) <> 1 then raise exception 'the consent was not revoked'; end if;
  perform public.set_offers_consent(false);  -- nothing to revoke: no error
  perform public.set_offers_consent(true, 'v2');
  if (select count(*) from public.terms_acceptances where person_id = me and document_type_id = offers) <> 2
     or (select count(*) from public.terms_acceptances where person_id = me and document_type_id = offers and revoked_at is null) <> 1 then
    raise exception 'the history must keep the revoked row and add a new active one';
  end if;
end
$$;

-- 4) Isolation and no API writes (A) / Aislamiento y sin escrituras por la API (A)
do $$
declare stmt text; denied boolean; me uuid := public.current_person_id();
begin
  if (select count(*) from public.terms_acceptances where person_id <> me) <> 0 then raise exception 'A can see acceptances of others'; end if;
  if (select count(*) from public.terms_acceptances) <> 5 then raise exception 'A must see exactly their own 5 rows (3 required + 2 offers)'; end if;
  foreach stmt in array array[
    $q$insert into public.terms_acceptances (person_id, document_type_id, version) values (public.current_person_id(), 4, 'x')$q$,
    $q$update public.terms_acceptances set revoked_at = now()$q$,
    $q$delete from public.terms_acceptances$q$,
    $q$insert into public.legal_document_types (code, is_required) values ('x', false)$q$,
    $q$update public.legal_document_types set is_required = false$q$,
    $q$delete from public.legal_document_types$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'authenticated could run: %', stmt; end if;
  end loop;
  if (select count(*) from public.legal_document_types) <> 4 then raise exception 'authenticated must read the document catalog'; end if;
end
$$;

-- 5) Unverified email and a login with the same email / mail sin verificar y otro login con el mismo mail
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.register_therapist('Beto', '{"terms":"1","privacy":"1","legal_declaration":"1"}'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'an unverified email registered'; end if;
end
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.register_therapist('Otra Ana', '{"terms":"1","privacy":"1","legal_declaration":"1"}'); exception when sqlstate '23505' then ok := true; end;
  if not ok then raise exception 'a second login with the same email registered'; end if;
end
$$;

-- 6) D registers WITH the offers consent / D se registra CON el consentimiento
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.register_therapist('Diego', '{"terms":"1","privacy":"1","legal_declaration":"1","offers_consent":"1"}');
do $$
begin
  if (select count(*) from public.terms_acceptances) <> 4 then raise exception 'D must see 4 acceptances (3 required + offers)'; end if;
end
$$;

-- 7) F is logged in but not registered: no person, so no consent changes / F con login pero sin ficha
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f6","role":"authenticated"}', true);
do $$
declare ok boolean := false;
begin
  begin perform public.set_offers_consent(true, 'v1'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'a login without a person gave a consent'; end if;
  if (select count(*) from public.terms_acceptances) <> 0 then raise exception 'F sees acceptances'; end if;
end
$$;
reset role;
reset session authorization;

-- 8) The admin reads all / el admin lee todo
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.terms_acceptances) <> 3 + 4 + 3 + 2 then raise exception 'the admin must see all 12 acceptances, saw %', (select count(*) from public.terms_acceptances); end if;
end
$$;
reset role;
reset session authorization;

-- 9) anon: nothing / anon: nada
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare stmt text; denied boolean;
begin
  foreach stmt in array array[
    $q$select * from public.terms_acceptances$q$,
    $q$select * from public.legal_document_types$q$,
    $q$insert into public.terms_acceptances (person_id, document_type_id, version) values (gen_random_uuid(), 1, 'x')$q$,
    $q$select public.register_therapist('Anon', '{}')$q$,
    $q$select public.set_offers_consent(true, 'v1')$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 10) Permissions of the functions and the table / permisos de funciones y tabla
do $$
declare f text;
begin
  foreach f in array array['public.register_therapist(text,jsonb)', 'public.set_offers_consent(boolean,text)'] loop
    if not has_function_privilege('authenticated', f, 'EXECUTE') then raise exception 'authenticated cannot execute %', f; end if;
    if has_function_privilege('anon', f, 'EXECUTE') or has_function_privilege('service_role', f, 'EXECUTE') then
      raise exception 'anon or service_role can execute %', f;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.terms_acceptances_guard()', 'EXECUTE')
     or has_function_privilege('anon', 'public.terms_acceptances_guard()', 'EXECUTE') then
    raise exception 'an API role can execute the trigger function';
  end if;
  if has_table_privilege('authenticated', 'public.terms_acceptances', 'INSERT') or has_table_privilege('authenticated', 'public.terms_acceptances', 'UPDATE')
     or has_table_privilege('authenticated', 'public.terms_acceptances', 'DELETE') or has_table_privilege('anon', 'public.terms_acceptances', 'SELECT')
     or has_table_privilege('service_role', 'public.terms_acceptances', 'SELECT') then
    raise exception 'unexpected privileges on terms_acceptances';
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
\echo 'OK: registration needs a verified email, required documents and keeps the evidence / el alta exige mail verificado, documentos obligatorios y conserva la evidencia'
