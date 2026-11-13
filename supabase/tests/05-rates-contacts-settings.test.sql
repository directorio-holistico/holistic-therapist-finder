-- Rates, contacts and settings: constraints, isolation, the only column anyone may write, anon denied.
-- Tarifas, contactos y ajustes: restricciones, aislamiento, la única columna que alguien puede escribir, anon denegado.
-- Run after Reset-LocalDb.ps1 (needs the dev seed) / Ejecutar después de Reset-LocalDb.ps1 (usa el seed).

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

-- 1) Maximum therapies (setting = 4 by default; then lowered) / Máximo de terapias (4 por defecto; luego se baja)
do $$
declare
  ok boolean;
  ids integer[] := array(select id from public.therapies order by id limit 5);
begin
  if array_length(ids, 1) < 5 then raise exception 'the dev seed must provide at least 5 therapies'; end if;
  insert into public.profile_therapies (profile_id, therapy_id) select '20000000-0000-0000-0000-0000000000a1', unnest(ids[1:4]);
  ok := false;
  begin insert into public.profile_therapies (profile_id, therapy_id) values ('20000000-0000-0000-0000-0000000000a1', ids[5]);
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a 5th therapy was accepted with the default limit of 4'; end if;
  -- another profile has its own count / otro perfil cuenta aparte
  insert into public.profile_therapies (profile_id, therapy_id) values ('20000000-0000-0000-0000-0000000000b2', ids[5]);
  -- lowering the setting applies to new rows / bajar el ajuste rige para filas nuevas
  update public.app_settings set value = '1' where key = 'max_therapies_per_profile';
  ok := false;
  begin insert into public.profile_therapies (profile_id, therapy_id) values ('20000000-0000-0000-0000-0000000000b2', ids[1]);
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'the lowered limit (1) was not applied'; end if;
  update public.app_settings set value = '4' where key = 'max_therapies_per_profile';
end
$$;

-- 2) Rates / Tarifas
do $$
declare
  ok boolean;
  p uuid := '20000000-0000-0000-0000-0000000000a1';
  t1 integer; t2 integer;
  own smallint := (select id from public.rate_audiences where code = 'own_country');
  other smallint := (select id from public.rate_audiences where code = 'other_countries');
  ars smallint := (select id from public.currencies where code = 'ARS');
  usd smallint := (select id from public.currencies where code = 'USD');
  clp smallint := (select id from public.currencies where code = 'CLP');
begin
  select therapy_id into t1 from public.profile_therapies where profile_id = p order by therapy_id limit 1;
  select therapy_id into t2 from public.profile_therapies where profile_id = p order by therapy_id desc limit 1;

  insert into public.profile_therapy_rates values (p, t1, own, 1000.50, ars);   -- valid / válida
  insert into public.profile_therapy_rates values (p, t1, other, 30, usd);      -- other audience, other currency / otra audiencia, otra moneda
  insert into public.profile_therapy_rates values (p, t2, own, 2000, ars);      -- same currency for the audience / misma moneda en la audiencia

  ok := false;  -- same audience, different currency in another therapy / misma audiencia, otra moneda en otra terapia
  begin insert into public.profile_therapy_rates values (p, t2, other, 25, ars); exception when check_violation then ok := true; end;
  if not ok then raise exception 'two currencies for one audience were accepted'; end if;

  ok := false;  -- negative amount / monto negativo
  begin update public.profile_therapy_rates set amount = -1 where profile_id = p and therapy_id = t1 and rate_audience_id = own;
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a negative amount was accepted'; end if;

  ok := false;  -- CLP has no decimals / CLP no tiene decimales
  begin
    update public.profile_therapy_rates set amount = 10.5, currency_id = clp where profile_id = p and therapy_id = t2 and rate_audience_id = own;
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'decimals in CLP were accepted'; end if;

  ok := false;  -- rate for a therapy the profile does not offer / tarifa de una terapia que el perfil no ofrece
  begin insert into public.profile_therapy_rates values (p, (select id from public.therapies where id not in (select therapy_id from public.profile_therapies where profile_id = p) limit 1), own, 1, ars);
  exception when foreign_key_violation then ok := true; end;
  if not ok then raise exception 'a rate without its therapy was accepted'; end if;
end
$$;

-- 3) Contacts / Contactos
do $$
declare
  ok boolean;
  a uuid := '20000000-0000-0000-0000-0000000000a1';
  b uuid := '20000000-0000-0000-0000-0000000000b2';
  phone smallint := (select id from public.contact_types where code = 'phone');
  mail smallint := (select id from public.contact_types where code = 'email');
  web smallint := (select id from public.contact_types where code = 'website');
  published smallint := (select id from public.profile_statuses where code = 'published');
  city integer := (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1);
begin
  -- invalid values / valores inválidos
  ok := false; begin insert into public.profile_contacts values (a, phone, 'abc', false); exception when check_violation then ok := true; end;
  if not ok then raise exception 'an invalid phone was accepted'; end if;
  ok := false; begin insert into public.profile_contacts values (a, mail, 'Mayus@Example.test', false); exception when check_violation then ok := true; end;
  if not ok then raise exception 'an upper-case email was accepted'; end if;
  ok := false; begin insert into public.profile_contacts values (a, web, 'www.example.test', false); exception when check_violation then ok := true; end;
  if not ok then raise exception 'a website without scheme was accepted'; end if;
  ok := false; begin insert into public.profile_contacts values (a, mail, 'a@example.test', true); exception when check_violation then ok := true; end;
  if not ok then raise exception 'accepts_whatsapp on an email was accepted'; end if;

  -- valid values / valores válidos
  insert into public.profile_contacts values (a, mail, 'a@example.test', false);
  insert into public.profile_contacts values (a, web, 'https://example.test/a', false);
  insert into public.profile_contacts values (b, phone, '+54 9 11 5555-0000', true);

  ok := false; begin insert into public.profile_contacts values (a, mail, 'otro@example.test', false); exception when unique_violation then ok := true; end;
  if not ok then raise exception 'two emails for one profile were accepted'; end if;

  -- publishing needs a phone: A has none yet / publicar necesita teléfono: A todavía no tiene
  ok := false;
  begin update public.therapist_profiles set status_id = published, approved_at = now(), location_id = city where id = a;
  exception when check_violation then ok := true; end;
  if not ok then raise exception 'a profile without phone was published'; end if;

  insert into public.profile_contacts values (a, phone, '+54 351 555 0101', true);
  update public.therapist_profiles set status_id = published, approved_at = now(), location_id = city where id = a;

  -- a published profile cannot lose its phone / un perfil publicado no puede perder el teléfono
  ok := false; begin delete from public.profile_contacts where profile_id = a and contact_type_id = phone; exception when check_violation then ok := true; end;
  if not ok then raise exception 'a published profile lost its phone'; end if;
  -- but deleting the whole profile cascades without error / pero borrar el perfil entero en cascada anda
  delete from public.therapist_profiles where id = a;
  if exists (select 1 from public.profile_contacts where profile_id = a) then raise exception 'cascade left contacts behind'; end if;
  -- recreate A for the isolation checks / se recrea A para las pruebas de aislamiento
  insert into public.therapist_profiles (id, person_id, status_id)
    values (a, '10000000-0000-0000-0000-0000000000a1', (select id from public.profile_statuses where code = 'unpublished'));
  insert into public.profile_therapies (profile_id, therapy_id) select a, id from public.therapies order by id limit 2;
  insert into public.profile_contacts values (a, phone, '+54 351 555 0101', true);
  insert into public.profile_therapy_rates select a, therapy_id, (select id from public.rate_audiences where code = 'own_country'), 1500, (select id from public.currencies where code = 'ARS')
    from public.profile_therapies where profile_id = a order by therapy_id limit 1;
  insert into public.profile_therapy_rates select b, therapy_id, (select id from public.rate_audiences where code = 'own_country'), 900, (select id from public.currencies where code = 'ARS')
    from public.profile_therapies where profile_id = b limit 1;
end
$$;

-- 4) Column-level write grants are an explicit allow-list / Los permisos de escritura por columna son una lista blanca explícita
do $$
begin
  if exists (
    select 1 from information_schema.role_column_grants
    where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
      and privilege_type in ('INSERT', 'UPDATE')
      and table_name <> 'restricted_terms'  -- table-level write grant (admin-only policies), reported here as column grants
      and not (grantee = 'authenticated' and (
            (table_name = 'app_settings' and column_name = 'value' and privilege_type = 'UPDATE')
         or (table_name = 'profile_revisions' and column_name in ('profile_id', 'payload', 'suggested_therapy') and privilege_type = 'INSERT')
         or (table_name = 'profile_revisions' and column_name in ('payload', 'suggested_therapy') and privilege_type = 'UPDATE')
         or (table_name = 'location_requests' and column_name in ('profile_id', 'region_id', 'city_name') and privilege_type = 'INSERT')
         or (table_name = 'location_requests' and column_name in ('region_id', 'city_name') and privilege_type = 'UPDATE')))
  ) then
    raise exception 'an API role has a column-level write grant outside the allow-list (app_settings.value, draft columns of profile_revisions, location_requests)';
  end if;
end
$$;

-- Private setting for the visibility checks / Ajuste privado para las pruebas de visibilidad
insert into public.app_settings (key, value, is_public, description) values ('zz_private', '1', false, 'test only');

-- 5) User A: own rates and contacts only; settings: public keys only; no writes.
-- 5) Usuario A: solo sus tarifas y contactos; ajustes: solo claves públicas; sin escrituras.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  stmt text;
  denied boolean;
  n integer;
begin
  if (select count(*) from public.profile_contacts) <> 1
     or (select profile_id from public.profile_contacts) <> '20000000-0000-0000-0000-0000000000a1' then
    raise exception 'A must see only their own contact';
  end if;
  if (select count(*) from public.profile_therapy_rates) <> 1 then raise exception 'A must see only their own rate'; end if;
  if (select count(*) from public.app_settings where key = 'max_therapies_per_profile') <> 1 then raise exception 'A must read the public setting'; end if;
  if (select count(*) from public.app_settings where key = 'zz_private') <> 0 then raise exception 'A can read a PRIVATE setting'; end if;

  update public.app_settings set value = '9' where key = 'max_therapies_per_profile';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'A changed a setting'; end if;

  foreach stmt in array array[
    $q$update public.profile_contacts set value = '+54 999 999 9999'$q$,
    $q$delete from public.profile_contacts$q$,
    $q$insert into public.profile_contacts values ('20000000-0000-0000-0000-0000000000a1', 2, 'x@example.test', false)$q$,
    $q$update public.profile_therapy_rates set amount = 1$q$,
    $q$delete from public.profile_therapy_rates$q$,
    $q$insert into public.app_settings (key, value, description) values ('hack', '1', 'x')$q$,
    $q$delete from public.app_settings$q$,
    $q$update public.app_settings set is_public = true$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'A could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 6) User B (mirror) / Usuario B (espejo)
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
do $$
begin
  if (select profile_id from public.profile_contacts) <> '20000000-0000-0000-0000-0000000000b2' then raise exception 'B must see only their own contact'; end if;
  if (select count(*) from public.profile_therapy_rates) <> 1 then raise exception 'B must see only their own rate'; end if;
end
$$;
reset role;
reset session authorization;

-- 7) Admin C: sees everything; changes only `value`, validated; cannot add or delete keys.
-- 7) Admin C: ve todo; cambia solo `value`, validado; no agrega ni borra claves.
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare
  n integer;
  stmt text;
  denied boolean;
  ok boolean;
begin
  if (select count(*) from public.profile_contacts) <> 2 or (select count(*) from public.profile_therapy_rates) <> 2 then
    raise exception 'admin must see all contacts and rates';
  end if;
  if (select count(*) from public.app_settings where key = 'zz_private') <> 1 then raise exception 'admin must read private settings'; end if;

  update public.app_settings set value = '3' where key = 'max_therapies_per_profile';
  get diagnostics n = row_count;
  if n <> 1 or (select value from public.app_settings where key = 'max_therapies_per_profile') <> '3' then
    raise exception 'admin could not change the value';
  end if;

  ok := false;
  begin update public.app_settings set value = '"abc"' where key = 'max_therapies_per_profile'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an invalid setting value was accepted'; end if;
  ok := false;
  begin update public.app_settings set value = '99' where key = 'max_therapies_per_profile'; exception when check_violation then ok := true; end;
  if not ok then raise exception 'an out of range setting value was accepted'; end if;

  foreach stmt in array array[
    $q$update public.app_settings set is_public = true$q$,
    $q$update public.app_settings set key = 'renamed'$q$,
    $q$insert into public.app_settings (key, value, description) values ('hack', '1', 'x')$q$,
    $q$delete from public.app_settings$q$,
    $q$delete from public.profile_contacts$q$
  ] loop
    denied := false;
    begin execute stmt; exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'admin could run: %', stmt; end if;
  end loop;
end
$$;
reset role;
reset session authorization;

-- 8) Visitor (anon): full tables denied; since commit 19 a few columns of published rows are public (tested in test 12)
-- 8) Visitante (anon): tablas completas denegadas; desde el commit 19 hay pocas columnas públicas (se prueban en el test 12)
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
declare
  t text;
  denied boolean;
begin
  foreach t in array array['profile_contacts', 'app_settings'] loop  -- rates expose all their columns, only for published rows (test 12)
    denied := false;
    begin execute format('select * from public.%I limit 1', t); exception when insufficient_privilege then denied := true; end;
    if not denied then raise exception 'anon could read all columns of %', t; end if;
  end loop;
  denied := false;
  begin perform 1 from public.app_settings limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'anon could read app_settings'; end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: rates, contacts and settings behave as designed / tarifas, contactos y ajustes segun el diseno'
