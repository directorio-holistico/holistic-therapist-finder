-- Therapy short names: column, constraints, public view, search function and grants.
-- Nombres cortos de terapia: columna, restricciones, vista pública, función de búsqueda y permisos.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- as owner: the column exists, is optional, LNT has its short name and only the listed therapies have one
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'therapy_translations'
                 and column_name = 'short_name' and is_nullable = 'YES') then
    raise exception 'short_name column missing or not nullable';
  end if;
  if (select tt.short_name from public.therapy_translations tt join public.therapies t on t.id = tt.therapy_id
       where t.code = 'lnt_schwiderski') is distinct from 'LNT®' then
    raise exception 'LNT short name not set';
  end if;
  -- rule instead of a fixed list or count: a short name must be shorter than the full name (otherwise it is not "short")
  -- regla en vez de lista o conteo fijo: el nombre corto debe ser más corto que el completo (si no, no es "corto")
  if exists (select 1 from public.therapy_translations tt
              where tt.short_name is not null and char_length(tt.short_name) >= char_length(tt.name)) then
    raise exception 'a short name is not shorter than the full name';
  end if;
  -- constraints: blank, padded and too long are rejected
  begin update public.therapy_translations set short_name = '' where therapy_id = (select id from public.therapies where code = 'reiki'); raise exception 'blank accepted';
  exception when check_violation then null; end;
  begin update public.therapy_translations set short_name = ' Reiki ' where therapy_id = (select id from public.therapies where code = 'reiki'); raise exception 'padded accepted';
  exception when check_violation then null; end;
  begin update public.therapy_translations set short_name = repeat('x', 41) where therapy_id = (select id from public.therapies where code = 'reiki'); raise exception 'too long accepted';
  exception when check_violation then null; end;
  -- grants of the search function did not change
  if not has_function_privilege('anon', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute')
     or has_function_privilege('service_role', 'public.search_profiles(integer,integer,text,integer,integer)', 'execute') then
    raise exception 'search_profiles grants changed';
  end if;
end $$;

-- a published profile with LNT and Reiki: the view and the search return aligned short names
insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-000000003001', 'sn1@example.test', now());
insert into public.people (id, auth_user_id, full_name, email)
  values ('10000000-0000-0000-0000-000000003001', '00000000-0000-0000-0000-000000003001', 'Persona sn1', 'sn1@example.test');
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, display_name)
  select '20000000-0000-0000-0000-000000003001', '10000000-0000-0000-0000-000000003001',
         (select id from public.profile_statuses where code = 'unpublished'), now(),
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id and ll.code = 'city' limit 1), 'Nombre Corto';
insert into public.profile_contacts (profile_id, contact_type_id, value)
  values ('20000000-0000-0000-0000-000000003001', (select id from public.contact_types where code = 'phone'), '+5435155503001');
insert into public.profile_therapies (profile_id, therapy_id, session_minutes)
  select '20000000-0000-0000-0000-000000003001', t.id, 60 from public.therapies t where t.code in ('lnt_schwiderski', 'reiki');
insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
  select '20000000-0000-0000-0000-000000003001', t.id, (select id from public.service_modes where code = 'remote')
  from public.therapies t where t.code in ('lnt_schwiderski', 'reiki');
insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id)
  select '20000000-0000-0000-0000-000000003001', t.id, (select id from public.session_formats where code = 'individual')
  from public.therapies t where t.code in ('lnt_schwiderski', 'reiki');
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id = '20000000-0000-0000-0000-000000003001';

-- as anonymous visitor / como visitante anónimo
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);

do $$
declare r record; failed boolean;
begin
  -- the view: names and short names are the same length and in the same order; LNT short, Reiki falls back to its name
  select * into r from public.public_profile_cards where profile_id = '20000000-0000-0000-0000-000000003001';
  if r.profile_id is null then raise exception 'profile not visible in the view'; end if;
  if cardinality(r.therapy_names) <> cardinality(r.therapy_short_names) or cardinality(r.therapy_names) <> 2 then
    raise exception 'names and short names not aligned: % / %', r.therapy_names, r.therapy_short_names;
  end if;
  if not ('LNT®' = any (r.therapy_short_names) and 'Reiki' = any (r.therapy_short_names)) then
    raise exception 'short names wrong: %', r.therapy_short_names;
  end if;
  if not ('LNT® - La Nueva Terapia - Método Schwiderski' = any (r.therapy_names)) then
    raise exception 'full name must stay in therapy_names: %', r.therapy_names;
  end if;
  -- same position: the short name at the position of the LNT full name is LNT®
  if r.therapy_short_names[array_position(r.therapy_names, 'LNT® - La Nueva Terapia - Método Schwiderski')] <> 'LNT®' then
    raise exception 'short names out of order';
  end if;

  -- the search returns the new column
  select * into r from public.search_profiles(null, null) s where s.profile_id = '20000000-0000-0000-0000-000000003001';
  if r.profile_id is null or not ('LNT®' = any (r.therapy_short_names)) then
    raise exception 'search_profiles does not return short names';
  end if;

  -- anon still cannot write the catalog
  failed := false;
  begin update public.therapy_translations set short_name = 'x'; exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'anon could write therapy_translations'; end if;
  -- anon cannot read the people table / anon sigue sin leer personas
  failed := false;
  begin perform 1 from public.people limit 1; exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'anon could read people'; end if;
end $$;

reset role;
reset session authorization;
rollback;
select 'OK 30-therapy-short-names' as result;
