-- Audit log: what is recorded, who did it, no personal values, append-only, roles, retention.
-- Registro de auditoría: qué se registra, quién lo hizo, sin valores personales, solo-agregar, roles, retención.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000006' || k)::uuid, k || '@example.test', now() from unnest(array['a1','ad']) k;
-- Setup as owner. These rows are logged too (actor null), so the checks below always filter by what they look at.
-- Preparación como dueño. Estas filas también se registran (actor nulo): las comprobaciones filtran lo que miran.
insert into public.people (id, auth_user_id, full_name, email) values
  ('10000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-0000000006a1', 'Canario Nombre Uno', 'canario-uno@example.test'),
  ('10000000-0000-0000-0000-0000000006ad', '00000000-0000-0000-0000-0000000006ad', 'Persona admin', 'ad6@example.test');
insert into public.person_roles (person_id, role_id) select '10000000-0000-0000-0000-0000000006ad'::uuid, id from public.roles where code = 'admin';
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  values ('20000000-0000-0000-0000-0000000006a1', '10000000-0000-0000-0000-0000000006a1',
          (select id from public.profile_statuses where code = 'unpublished'), now() - interval '10 days',
          (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1), 'Perfil Canario');
insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
  select '20000000-0000-0000-0000-0000000006a1'::uuid, ct.id, '+54 351 555 0601', false from public.contact_types ct where ct.code = 'phone';

-- 1) STRUCTURE (as owner) / ESTRUCTURA
do $$
declare r text; p text; t text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.audit_log'::regclass) then raise exception 'audit_log has no RLS'; end if;
  if (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
       where table_schema = 'public' and table_name = 'audit_log')
     <> array['id', 'occurred_at', 'table_name', 'operation', 'row_key', 'changed_fields', 'detail', 'actor_person_id', 'actor_role'] then
    raise exception 'audit_log columns changed: any new column must be reviewed for personal data';
  end if;
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    foreach p in array array['insert', 'update', 'delete', 'truncate'] loop
      if has_table_privilege(r, 'public.audit_log', p) then raise exception '% has % on audit_log', r, p; end if;
    end loop;
  end loop;
  if has_table_privilege('anon', 'public.audit_log', 'select') or has_table_privilege('service_role', 'public.audit_log', 'select')
     or not has_table_privilege('authenticated', 'public.audit_log', 'select') then
    raise exception 'only authenticated (admin by policy) may select audit_log';
  end if;
  if (select count(*) from pg_policy where polrelid = 'public.audit_log'::regclass) <> 1 then raise exception 'audit_log must have exactly one policy (admin select)'; end if;
  -- exactly these tables are audited, each with an AFTER ROW trigger for insert, update and delete
  -- exactamente estas tablas se auditan, cada una con un trigger AFTER ROW para insert, update y delete
  if (select array_agg(c.relname::text order by c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and t.tgfoid = 'public.audit_row_change()'::regprocedure)
     <> array['app_settings', 'location_requests', 'people', 'person_roles', 'profile_contacts', 'restricted_terms', 'therapist_profiles'] then
    raise exception 'the set of audited tables changed';
  end if;
  for t in select t.tgname from pg_trigger t where not t.tgisinternal and t.tgfoid = 'public.audit_row_change()'::regprocedure loop
    if not exists (select 1 from pg_trigger x where x.tgname = t and x.tgfoid = 'public.audit_row_change()'::regprocedure
                    and (x.tgtype & 1) = 1 and (x.tgtype & 2) = 0            -- row level, AFTER
                    and (x.tgtype & 4) = 4 and (x.tgtype & 8) = 8 and (x.tgtype & 16) = 16) then
      raise exception 'trigger % must be AFTER ROW for insert, update and delete', t;
    end if;
  end loop;
  if (select count(*) from pg_trigger where tgrelid = 'public.audit_log'::regclass and not tgisinternal and tgfoid = 'public.audit_log_protect()'::regprocedure) <> 2 then
    raise exception 'audit_log needs its two protection triggers (row and truncate)';
  end if;
  foreach t in array array['public.audit_row_change()', 'public.audit_log_protect()', 'public.purge_expired_audit_log()'] loop
    if not (select prosecdef from pg_proc where oid = t::regprocedure) then raise exception '% must be SECURITY DEFINER', t; end if;
    if not exists (select 1 from pg_proc where oid = t::regprocedure and proconfig @> array['search_path=pg_catalog, public']) then raise exception '% needs a fixed search_path', t; end if;
    if has_function_privilege('anon', t, 'execute') or has_function_privilege('authenticated', t, 'execute') then raise exception '% executable by an API role', t; end if;
  end loop;
  if not has_function_privilege('service_role', 'public.purge_expired_audit_log()', 'execute')
     or has_function_privilege('service_role', 'public.audit_row_change()', 'execute')
     or has_function_privilege('service_role', 'public.audit_log_protect()', 'execute') then
    raise exception 'only the purge is executable by service_role';
  end if;
  -- the setting / el ajuste
  if (select value::text from public.app_settings where key = 'retention_audit_months') <> '24' then raise exception 'default retention must be 24 months'; end if;
  if (select is_public from public.app_settings where key = 'retention_audit_months') then raise exception 'retention_audit_months must be private'; end if;
  foreach t in array array['0', '121', '-1', '1.5', '"dos"', 'true', 'null'] loop
    begin update public.app_settings set value = t::jsonb where key = 'retention_audit_months'; raise exception 'retention % accepted', t;
    exception when check_violation then null; end;
  end loop;
end $$;

-- 2) WHAT IS RECORDED (as owner, actor null) / QUÉ SE REGISTRA
do $$
declare n int; a public.audit_log;
begin
  -- the setup inserts are there: INSERT, key = id, no changed fields, no values
  select * into a from public.audit_log where table_name = 'people' and row_key = '10000000-0000-0000-0000-0000000006a1';
  if a.operation is distinct from 'INSERT' or a.changed_fields is not null or a.detail is not null or a.actor_person_id is not null or a.actor_role is not null then
    raise exception 'people INSERT record is wrong: %', to_jsonb(a);
  end if;
  -- composite keys / claves compuestas
  select count(*) into n from public.audit_log where table_name = 'person_roles'
     and row_key = '10000000-0000-0000-0000-0000000006ad:' || (select id from public.roles where code = 'admin') and operation = 'INSERT';
  if n <> 1 then raise exception 'person_roles key must be person_id:role_id'; end if;
  select count(*) into n from public.audit_log where table_name = 'profile_contacts'
     and row_key = '20000000-0000-0000-0000-0000000006a1:' || (select id from public.contact_types where code = 'phone');
  if n <> 1 then raise exception 'profile_contacts key must be profile_id:contact_type_id'; end if;

  delete from public.audit_log where false;  -- a no-op delete must not be blocked by the protection trigger (no rows) / un delete vacío no se bloquea
end $$;
do $$
declare before_n bigint; a public.audit_log;
begin
  -- an UPDATE that changes nothing leaves no record / un UPDATE que no cambia nada no deja registro
  select count(*) into before_n from public.audit_log;
  update public.people set full_name = full_name where id = '10000000-0000-0000-0000-0000000006a1';
  if (select count(*) from public.audit_log) <> before_n then raise exception 'a no-change update was recorded'; end if;
  -- an UPDATE names ONLY the columns that changed, never their values / un UPDATE nombra SOLO las columnas cambiadas, nunca sus valores
  update public.people set full_name = 'Canario Nombre Dos', email = 'canario-dos@example.test' where id = '10000000-0000-0000-0000-0000000006a1';
  select * into a from public.audit_log where table_name = 'people' and operation = 'UPDATE' order by id desc limit 1;
  if a.row_key is distinct from '10000000-0000-0000-0000-0000000006a1' or a.changed_fields is distinct from array['email', 'full_name'] or a.detail is not null then
    raise exception 'people UPDATE record is wrong: %', to_jsonb(a);
  end if;
  update public.profile_contacts set value = '+54 351 555 0699', accepts_whatsapp = true where profile_id = '20000000-0000-0000-0000-0000000006a1';
  select * into a from public.audit_log where table_name = 'profile_contacts' and operation = 'UPDATE' order by id desc limit 1;
  if a.changed_fields is distinct from array['accepts_whatsapp', 'value'] or a.detail is not null then raise exception 'profile_contacts UPDATE record is wrong: %', to_jsonb(a); end if;
  update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'paused'), status_reason = 'canario motivo' where id = '20000000-0000-0000-0000-0000000006a1';
  select * into a from public.audit_log where table_name = 'therapist_profiles' and operation = 'UPDATE' order by id desc limit 1;
  if a.changed_fields is distinct from array['status_id', 'status_reason'] then raise exception 'therapist_profiles UPDATE record is wrong: %', to_jsonb(a); end if;
  -- restricted terms: the word itself is not stored either / términos restringidos: la palabra tampoco se guarda
  insert into public.restricted_terms (term) values ('canarioterm');
  update public.restricted_terms set note = 'canario nota' where term = 'canarioterm';
  delete from public.restricted_terms where term = 'canarioterm';
  if (select string_agg(operation, ',' order by id) from public.audit_log where table_name = 'restricted_terms' and id > (select max(id) - 3 from public.audit_log)) <> 'INSERT,UPDATE,DELETE' then
    raise exception 'restricted_terms insert/update/delete not all recorded';
  end if;
  -- app_settings is the only table that keeps values (old and new) / app_settings es la única tabla que guarda valores
  update public.app_settings set value = '30' where key = 'reveal_daily_limit';
  select * into a from public.audit_log where table_name = 'app_settings' and operation = 'UPDATE' order by id desc limit 1;
  if a.row_key is distinct from 'reveal_daily_limit' or a.changed_fields is distinct from array['value'] or a.detail is distinct from '{"old": 20, "new": 30}'::jsonb then
    raise exception 'app_settings UPDATE record is wrong: %', to_jsonb(a);
  end if;
  update public.app_settings set value = '20' where key = 'reveal_daily_limit';
  -- settings insert and delete keep the value too; a key change is recorded under the NEW key
  -- insert y delete de un ajuste también guardan el valor; un cambio de clave se registra con la clave NUEVA
  insert into public.app_settings (key, value, is_public, description) values ('zz_audit_probe', '7', false, 'probe');
  select * into a from public.audit_log where table_name = 'app_settings' and operation = 'INSERT' order by id desc limit 1;
  if a.row_key is distinct from 'zz_audit_probe' or a.detail is distinct from '{"new": 7}'::jsonb or a.changed_fields is not null then raise exception 'app_settings INSERT record is wrong: %', to_jsonb(a); end if;
  update public.app_settings set key = 'zz_audit_probe2' where key = 'zz_audit_probe';
  select * into a from public.audit_log where table_name = 'app_settings' and operation = 'UPDATE' order by id desc limit 1;
  if a.row_key is distinct from 'zz_audit_probe2' or a.changed_fields is distinct from array['key'] then raise exception 'key change must be recorded under the new key: %', to_jsonb(a); end if;
  delete from public.app_settings where key = 'zz_audit_probe2';
  select * into a from public.audit_log where table_name = 'app_settings' and operation = 'DELETE' order by id desc limit 1;
  if a.row_key is distinct from 'zz_audit_probe2' or a.detail is distinct from '{"old": 7}'::jsonb or a.changed_fields is not null then raise exception 'app_settings DELETE record is wrong: %', to_jsonb(a); end if;
  -- delete / borrado
  delete from public.profile_contacts where profile_id = '20000000-0000-0000-0000-0000000006a1';
  select * into a from public.audit_log where table_name = 'profile_contacts' and operation = 'DELETE' order by id desc limit 1;
  if a.changed_fields is not null or a.detail is not null then raise exception 'profile_contacts DELETE record is wrong: %', to_jsonb(a); end if;
  -- NO personal value anywhere in the whole table / NINGÚN valor personal en toda la tabla
  if exists (select 1 from public.audit_log where to_jsonb(audit_log)::text ~* '(canario|example\.test|555 0|@)') then
    raise exception 'the audit log holds a personal value: %', (select to_jsonb(x)::text from public.audit_log x where to_jsonb(x)::text ~* '(canario|example\.test|555 0|@)' limit 1);
  end if;
end $$;

-- 3) WHO: through the API (admin) and through the server (service_role) / QUIÉN: por la API (admin) y por el servidor
set session authorization authenticator;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006ad","role":"authenticated"}', true);
do $$
declare a public.audit_log;
begin
  update public.app_settings set value = '25' where key = 'reveal_daily_limit';
  select * into a from public.audit_log where table_name = 'app_settings' and operation = 'UPDATE' order by id desc limit 1;
  if a.actor_person_id is distinct from '10000000-0000-0000-0000-0000000006ad' or a.actor_role is distinct from 'authenticated' or a.detail is distinct from '{"old": 20, "new": 25}'::jsonb then
    raise exception 'admin setting change attributed wrongly: %', to_jsonb(a);
  end if;
  insert into public.restricted_terms (term) values ('terminoadmin');
  select * into a from public.audit_log where table_name = 'restricted_terms' and operation = 'INSERT' order by id desc limit 1;
  if a.actor_person_id is distinct from '10000000-0000-0000-0000-0000000006ad' or a.actor_role is distinct from 'authenticated' then raise exception 'admin term insert attributed wrongly: %', to_jsonb(a); end if;
  -- the admin reads the log, and cannot write or erase it / el admin lo lee, y no puede escribirlo ni borrarlo
  if (select count(*) from public.audit_log) < 5 then raise exception 'the admin cannot read the audit log'; end if;
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'INSERT', 'x'); raise exception 'admin inserted into audit_log';
  exception when insufficient_privilege then null; end;
  begin update public.audit_log set row_key = 'x'; raise exception 'admin updated audit_log';
  exception when insufficient_privilege then null; end;
  begin delete from public.audit_log; raise exception 'admin deleted from audit_log';
  exception when insufficient_privilege then null; end;
  begin truncate public.audit_log; raise exception 'admin truncated audit_log';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_audit_log(); raise exception 'admin ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
-- the therapist sees nothing (no row passes the policy) and writes nothing / el terapeuta no ve nada y no escribe nada
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a1","role":"authenticated"}', true);
do $$
begin
  if (select count(*) from public.audit_log) <> 0 then raise exception 'a therapist reads the audit log'; end if;
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'INSERT', 'x'); raise exception 'therapist inserted into audit_log';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_audit_log(); raise exception 'therapist ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform 1 from public.audit_log; raise exception 'anon read audit_log';
  exception when insufficient_privilege then null; end;
  begin perform public.purge_expired_audit_log(); raise exception 'anon ran the purge';
  exception when insufficient_privilege then null; end;
end $$;
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
begin
  begin perform 1 from public.audit_log; raise exception 'service_role read audit_log directly';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
reset session authorization;

-- 3b) the server erases a therapist: attributed to service_role, and the log stays free of personal values
-- el servidor elimina a un terapeuta: se atribuye a service_role y el registro sigue sin valores personales
set session authorization authenticator;
set role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select auth_user_id from public.erase_therapist('10000000-0000-0000-0000-0000000006a1',
  jsonb_build_array(jsonb_build_object('type', 'email', 'hash', repeat('a', 64))), 'self');
reset role;
reset session authorization;
do $$
declare a public.audit_log;
begin
  select * into a from public.audit_log where table_name = 'people' and row_key = '10000000-0000-0000-0000-0000000006a1' and operation = 'UPDATE' order by id desc limit 1;
  if a.actor_role is distinct from 'service_role' or a.actor_person_id is not null or not coalesce(a.changed_fields @> array['email', 'full_name', 'erased_at'], false) then
    raise exception 'erasure of the person recorded wrongly: %', to_jsonb(a);
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'therapist_profiles' and operation = 'DELETE' and row_key = '20000000-0000-0000-0000-0000000006a1' and actor_role = 'service_role') then
    raise exception 'the deletion of the profile was not recorded';
  end if;
  if exists (select 1 from public.audit_log where to_jsonb(audit_log)::text ~* '(canario|example\.test|555 0|@|Persona eliminada)') then
    raise exception 'the audit log keeps a personal value after the erasure';
  end if;
end $$;

-- 4) APPEND-ONLY, even for the owner / SOLO-AGREGAR, incluso para el dueño
do $$
begin
  begin update public.audit_log set row_key = 'x'; raise exception 'owner updated audit_log';
  exception when insufficient_privilege then null; end;
  begin delete from public.audit_log; raise exception 'owner deleted from audit_log';
  exception when insufficient_privilege then null; end;
  begin truncate public.audit_log; raise exception 'owner truncated audit_log';
  exception when insufficient_privilege then null; end;
  -- the flag alone does not open the door for UPDATE / la marca sola no abre la puerta para UPDATE
  perform set_config('app.audit_purge', 'on', true);
  begin update public.audit_log set row_key = 'x'; raise exception 'flag allowed an update';
  exception when insufficient_privilege then null; end;
  begin truncate public.audit_log; raise exception 'flag allowed a truncate';
  exception when insufficient_privilege then null; end;
  perform set_config('app.audit_purge', 'off', true);
  -- constraints: updates name columns, only app_settings carries values / restricciones
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'UPDATE', 'x'); raise exception 'UPDATE without changed fields accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key, changed_fields) values ('people', 'INSERT', 'x', array['a']); raise exception 'INSERT with changed fields accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key, changed_fields) values ('people', 'UPDATE', 'x', array[]::text[]); raise exception 'UPDATE with empty changed fields accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key, detail) values ('people', 'INSERT', 'x', '{"old": "Ana"}'); raise exception 'values accepted outside app_settings';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'INSERT', ''); raise exception 'empty row key accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'INSERT', repeat('k', 201)); raise exception 'long row key accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key) values ('People', 'INSERT', 'x'); raise exception 'bad table name accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key) values ('people', 'MERGE', 'x'); raise exception 'bad operation accepted';
  exception when check_violation then null; end;
  begin insert into public.audit_log (table_name, operation, row_key, actor_role) values ('people', 'INSERT', 'x', 'Service Role'); raise exception 'bad actor role accepted';
  exception when check_violation then null; end;
end $$;

-- 5) RETENTION (purge by service_role) / RETENCIÓN
insert into public.audit_log (occurred_at, table_name, operation, row_key) values
  (now() - interval '25 months', 'people', 'INSERT', 'old-1'),
  (now() - interval '24 months' - interval '1 day', 'people', 'INSERT', 'old-2'),
  (now() - interval '23 months', 'people', 'INSERT', 'keep-1');
set session authorization authenticator;
set role service_role;
do $$
declare removed int;
begin
  removed := public.purge_expired_audit_log();
  if removed <> 2 then raise exception 'purge should remove 2 rows (older than 24 months), removed %', removed; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if exists (select 1 from public.audit_log where row_key in ('old-1', 'old-2')) or not exists (select 1 from public.audit_log where row_key = 'keep-1') then
    raise exception 'purge removed the wrong rows';
  end if;
  if exists (select 1 from public.audit_log where occurred_at < now() - interval '24 months') then raise exception 'an expired row survived the purge'; end if;
  -- the purge flag is off again: the door is closed after it / la marca queda apagada: la puerta se cierra después
  if coalesce(current_setting('app.audit_purge', true), '') = 'on' then raise exception 'the purge flag stayed on'; end if;
  begin delete from public.audit_log; raise exception 'delete allowed after the purge';
  exception when insufficient_privilege then null; end;
  -- a shorter retention removes more / una retención menor borra más
  update public.app_settings set value = '12' where key = 'retention_audit_months';
end $$;
set session authorization authenticator;
set role service_role;
do $$
begin
  if public.purge_expired_audit_log() < 1 then raise exception 'purge with 12 months should remove keep-1 (23 months old)'; end if;
end $$;
reset role;
reset session authorization;
do $$
begin
  if exists (select 1 from public.audit_log where row_key = 'keep-1') then raise exception 'keep-1 survived a 12-month purge'; end if;
  -- recent records are never purged / los registros recientes no se purgan
  if not exists (select 1 from public.audit_log where table_name = 'app_settings') then raise exception 'recent records were purged'; end if;
  delete from public.app_settings where key = 'retention_audit_months';
end $$;
set session authorization authenticator;
set role service_role;
do $$
begin
  begin perform public.purge_expired_audit_log(); raise exception 'purge ran without its setting';
  exception when check_violation then null; end;
end $$;
reset role;
reset session authorization;

-- 6) NO FOREIGN KEY: deleting a person who appears as an actor works, and the records stay
-- 6) SIN CLAVE FORÁNEA: borrar a una persona que figura como actor funciona, y los registros quedan
do $$
declare before_n int;
begin
  select count(*) into before_n from public.audit_log where actor_person_id = '10000000-0000-0000-0000-0000000006ad';
  if before_n < 1 then raise exception 'the test needs audit rows of the admin as actor'; end if;
  delete from public.people where id = '10000000-0000-0000-0000-0000000006ad';
  if (select count(*) from public.audit_log where actor_person_id = '10000000-0000-0000-0000-0000000006ad') <> before_n then
    raise exception 'audit rows changed when the actor person was deleted';
  end if;
end $$;

rollback;
select 'OK 18-audit-log' as result;
