-- Admin adds / hides / shows therapies: who may, what the functions refuse, what visitors see, what the audit log records.
-- El admin agrega / oculta / muestra terapias: quién puede, qué rechazan las funciones, qué ven los visitantes, qué registra la auditoría.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000037' || k)::uuid, k || '@example.test', now() from unnest(array['a1','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000037' || k)::uuid, ('00000000-0000-0000-0000-0000000037' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','ad']) k;
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000037ad'::uuid, id from public.roles where code = 'admin';

-- 1) ANON: neither function, and no direct write / ANON: ninguna función, ni escritura directa
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform public.admin_add_therapy('zz_anon', 'Anon');
    raise exception 'anon must not execute admin_add_therapy';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_therapy_active(1, false);
    raise exception 'anon must not execute admin_set_therapy_active';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 2) a1 (not an administrator): refused by the function itself, and no direct write either
-- 2) a1 (no es administrador): lo rechaza la propia función, y tampoco puede escribir directo
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000037a1","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.admin_add_therapy('zz_user', 'Usuario');
    raise exception 'a non-admin must not add a therapy';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.admin_set_therapy_active((select min(id) from public.therapies), false);
    raise exception 'a non-admin must not hide a therapy';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.therapies (code) values ('zz_direct');
    raise exception 'authenticated must not write the catalog directly';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 3) ad (administrator): adds and validations. State is checked as owner below (RLS may hide hidden therapies from this role).
-- 3) ad (administrador): altas y validaciones. El estado se comprueba como dueño más abajo (RLS puede ocultarle terapias ocultas a este rol).
select set_config('test.top', (select max(sort_order) from public.therapies)::text, true);
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000037ad","role":"authenticated"}', true);
do $$
declare
  new_id integer;
begin
  new_id := public.admin_add_therapy('zz_new_therapy', 'Terapia de prueba 37', 'Prueba 37');
  if new_id is null then raise exception 'the function must return the new id'; end if;
  perform set_config('test.new_id', new_id::text, true);
  -- hidden from the start / oculta desde el inicio
  perform public.admin_add_therapy('zz_hidden_therapy', 'Terapia oculta 37', null, null, false);
  -- duplicates: same code, same name with other capitals / repetidos: mismo código, mismo nombre con otras mayúsculas
  begin perform public.admin_add_therapy('zz_new_therapy', 'Otro nombre 37'); raise exception 'duplicate code accepted';
  exception when unique_violation then null; end;
  begin perform public.admin_add_therapy('zz_other_code', 'terapia DE prueba 37'); raise exception 'duplicate name accepted';
  exception when unique_violation then null; end;
  -- validations (22023) / validaciones (22023)
  begin perform public.admin_add_therapy('Mal Codigo', 'Nombre 37'); raise exception 'bad code accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.admin_add_therapy(null, 'Nombre 37'); raise exception 'null code accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.admin_add_therapy('zz_v1', ' con espacios '); raise exception 'name with edge spaces accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.admin_add_therapy('zz_v2', ''); raise exception 'empty name accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.admin_add_therapy('zz_v3', 'Nombre 37', repeat('x', 41)); raise exception 'long short name accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.admin_add_therapy('zz_v4', 'Nombre 37', null, 0::smallint); raise exception 'sort order 0 accepted';
  exception when sqlstate '22023' then null; end;
end
$$;
reset role;
reset session authorization;

-- 3b) as owner: stored as expected; the failed adds left nothing / como dueño: guardado como se esperaba; los altas fallidas no dejaron nada
do $$
begin
  if not exists (select 1 from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id
                 join public.languages l on l.id = tt.language_id and l.code = 'es'
                 where t.id = current_setting('test.new_id')::int and t.code = 'zz_new_therapy' and t.is_active
                   and t.sort_order = current_setting('test.top')::int + 10
                   and tt.name = 'Terapia de prueba 37' and tt.short_name = 'Prueba 37') then
    raise exception 'the new therapy was not stored as expected (active, last in the list, names)';
  end if;
  if (select is_active from public.therapies where code = 'zz_hidden_therapy') is distinct from false then raise exception 'must be created hidden'; end if;
  if exists (select 1 from public.therapies where code in ('zz_other_code', 'zz_v1', 'zz_v2', 'zz_v3', 'zz_v4')) then raise exception 'a failed add left a therapy behind'; end if;
end
$$;

-- 4) ad hides the new therapy; a visitor no longer sees it / ad oculta la terapia nueva; el visitante ya no la ve
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000037ad","role":"authenticated"}', true);
select public.admin_set_therapy_active(current_setting('test.new_id')::int, false);
reset role;
reset session authorization;
do $$
begin
  if (select is_active from public.therapies where id = current_setting('test.new_id')::int) then raise exception 'must be hidden'; end if;
end
$$;
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if exists (select 1 from public.therapy_translations where name in ('Terapia de prueba 37', 'Terapia oculta 37')) then raise exception 'anon must not see a hidden therapy name'; end if;
  if exists (select 1 from public.therapies where code in ('zz_new_therapy', 'zz_hidden_therapy')) then raise exception 'anon must not see a hidden therapy'; end if;
end
$$;
reset role;
reset session authorization;

-- 5) ad: unknown id, bad arguments, shows it again; the visitor sees it / ad: id inexistente, argumentos malos, la muestra de nuevo; el visitante la ve
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000037ad","role":"authenticated"}', true);
do $$
begin
  begin perform public.admin_set_therapy_active(-1, true); raise exception 'unknown therapy accepted';
  exception when sqlstate 'P0002' then null; end;
  begin perform public.admin_set_therapy_active(current_setting('test.new_id')::int, null); raise exception 'null flag accepted';
  exception when sqlstate '22023' then null; end;
  perform public.admin_set_therapy_active(current_setting('test.new_id')::int, true);
end
$$;
reset role;
reset session authorization;
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if not exists (select 1 from public.therapy_translations where name = 'Terapia de prueba 37') then raise exception 'anon must see the shown therapy'; end if;
  if exists (select 1 from public.therapy_translations where name = 'Terapia oculta 37') then raise exception 'anon must still not see the hidden-from-start therapy'; end if;
end
$$;
reset role;
reset session authorization;

-- 6) The audit log recorded WHO did it, with no personal value / La auditoría registró QUIÉN lo hizo, sin valores personales
do $$
begin
  if not exists (select 1 from public.audit_log where table_name = 'therapies' and operation = 'INSERT'
                 and row_key = current_setting('test.new_id') and actor_person_id = '10000000-0000-0000-0000-0000000037ad') then
    raise exception 'the audit log must record who added the therapy';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'therapies' and operation = 'UPDATE'
                 and row_key = current_setting('test.new_id') and actor_person_id = '10000000-0000-0000-0000-0000000037ad'
                 and changed_fields @> array['is_active']) then
    raise exception 'the audit log must record who hid / showed the therapy (column name only)';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'therapy_translations' and operation = 'INSERT'
                 and actor_person_id = '10000000-0000-0000-0000-0000000037ad') then
    raise exception 'the audit log must record the translation insert';
  end if;
end
$$;

rollback;
\echo 'OK: therapy administration behaves as designed / la administración de terapias se comporta como se diseñó'
