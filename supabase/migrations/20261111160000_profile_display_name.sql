-- Public display name of a profile. SECURITY CHANGE: replaces 3 existing functions (same permissions).
-- Nombre público del perfil. CAMBIO DE SEGURIDAD: reemplaza 3 funciones existentes (mismos permisos).
--
-- Why / Por qué: the public views (next commit) must show a name without reading people, which holds the emails.
-- So the profile carries its own public name. It is a profile field: it changes only through a moderated revision.
-- las vistas públicas (próximo commit) deben mostrar un nombre sin leer people, que guarda los mails. Por eso el perfil
-- lleva su propio nombre público. Es un campo del perfil: cambia solo con una revisión moderada.
--
-- Rules / Reglas:
--  * At creation the profile copies the person's name (the therapist can then change it through a revision).
--    Al crearse, el perfil copia el nombre de la persona (el terapeuta puede cambiarlo con una revisión).
--  * A published profile needs a display name; a revision can set it or (on an unpublished profile) clear it.
--    Un perfil publicado necesita nombre público.
--  * Replaced with create or replace, so existing EXECUTE grants are kept (the tests check them again):
--    therapist_profiles_guard (trigger), submit_revision and apply_revision_payload (new payload key "display_name").
--    Se reemplazan con create or replace, así se conservan los permisos (las pruebas los verifican de nuevo).

alter table public.therapist_profiles
  add column display_name text check (display_name = btrim(display_name) and char_length(display_name) between 1 and 80);
comment on column public.therapist_profiles.display_name is
  'Public name shown in search results; starts as the person name / Nombre público que se muestra en las búsquedas; empieza como el nombre de la persona.';

update public.therapist_profiles tp set display_name = btrim(left(p.full_name, 80))
  from public.people p where p.id = tp.person_id and tp.display_name is null and p.erased_at is null;

create or replace function public.therapist_profiles_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  status_code text;
  level_code  text;
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      raise exception 'profiles are created by the server, not by API roles' using errcode = '42501';
    end if;
    if new.person_id is distinct from old.person_id
       or new.status_id is distinct from old.status_id
       or new.approved_at is distinct from old.approved_at
       or new.status_reason is distinct from old.status_reason then
      raise exception 'privilege fields cannot be changed by API roles' using errcode = '42501';
    end if;
  end if;
  -- a new profile starts with the person name as its public name / un perfil nuevo empieza con el nombre de la persona
  if tg_op = 'INSERT' and new.display_name is null then
    select btrim(left(p.full_name, 80)) into new.display_name from public.people p where p.id = new.person_id and p.erased_at is null;
  end if;
  if new.location_id is not null then
    select ll.code into level_code
      from public.locations l join public.location_levels ll on ll.id = l.level_id
      where l.id = new.location_id;
    if level_code is distinct from 'city' then
      raise exception 'the base location of a profile must be a city' using errcode = '23514';
    end if;
  end if;

  select code into status_code from public.profile_statuses where id = new.status_id;
  if status_code = 'published' then
    if new.approved_at is null or new.location_id is null then
      raise exception 'a published profile needs approved_at and a location' using errcode = '23514';
    end if;
    if new.display_name is null then
      raise exception 'a published profile needs a display name' using errcode = '23514';
    end if;
    if not exists (
      select 1 from public.profile_contacts pc join public.contact_types ct on ct.id = pc.contact_type_id
      where pc.profile_id = new.id and ct.code = 'phone') then
      raise exception 'a published profile needs a phone' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

-- submit_revision: same as before, with "display_name" among the known payload keys.
-- submit_revision: igual que antes, con "display_name" entre las claves conocidas.
create or replace function public.submit_revision(p_revision_id uuid)
returns text[]
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person        uuid := public.current_person_id();
  rev           public.profile_revisions%rowtype;
  profile_row   public.therapist_profiles%rowtype;
  profile_status text;
  draft_id      smallint;
  pending_id    smallint;
  allowed_keys  constant text[] := array['display_name', 'headline', 'zone', 'practice_start_year', 'location_id',
                                          'photo_path', 'therapies', 'languages', 'service_modes', 'session_formats', 'contacts'];
  unknown_keys  text[];
  all_text      text;
  flagged       text[];
  days_setting  text;
  days          integer;
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;

  select r.* into rev
    from public.profile_revisions r
    join public.therapist_profiles tp on tp.id = r.profile_id
    where r.id = p_revision_id and tp.person_id = person
    for update of r;
  if not found then
    raise exception 'revision not found' using errcode = 'P0002';
  end if;

  select id into strict draft_id from public.revision_statuses where code = 'draft';
  select id into strict pending_id from public.revision_statuses where code = 'pending_review';
  if rev.status_id <> draft_id then
    raise exception 'only a draft can be submitted' using errcode = '55000';
  end if;

  select * into profile_row from public.therapist_profiles where id = rev.profile_id;
  select code into strict profile_status from public.profile_statuses where id = profile_row.status_id;
  if profile_status in ('suspended', 'erased') then
    raise exception 'a % profile cannot submit revisions', profile_status using errcode = '55000';
  end if;

  -- the payload must have content and only known top-level keys (full validation happens when it is approved)
  -- el payload debe tener contenido y solo claves conocidas (la validación completa ocurre al aprobarlo)
  if rev.payload = '{}'::jsonb then
    raise exception 'the revision is empty' using errcode = '22023';
  end if;
  select array_agg(k) into unknown_keys from jsonb_object_keys(rev.payload) k where k <> all (allowed_keys);
  if unknown_keys is not null then
    raise exception 'unknown payload keys: %', unknown_keys using errcode = '22023';
  end if;

  -- every text in the payload plus the suggested therapy is checked against the restricted terms
  -- cada texto del payload más la terapia sugerida se compara con los términos restringidos
  select concat_ws(' ',
           (select string_agg(v #>> '{}', ' ') from jsonb_path_query(rev.payload, 'strict $.**') v
             where jsonb_typeof(v) = 'string'),
           rev.suggested_therapy)
    into all_text;
  flagged := public.match_restricted_terms(all_text);

  select case
           when rev.is_priority then 'review_days_priority'
           when profile_row.approved_at is null then 'review_days_initial'
           else 'review_days_update'
         end
    into days_setting;
  select (value::text)::int into days from public.app_settings where key = days_setting;
  if days is null then
    raise exception 'setting % is missing', days_setting using errcode = '23514';
  end if;

  update public.profile_revisions
     set status_id = pending_id,
         flagged_terms = flagged,
         submitted_at = now(),
         due_at = public.add_business_days(now(), days)
   where id = rev.id;
  return flagged;
end
$$;

-- apply_revision_payload: same as before, plus the "display_name" key.
-- apply_revision_payload: igual que antes, más la clave "display_name".
create or replace function public.apply_revision_payload(p_profile_id uuid, p_payload jsonb)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  elem   jsonb;
  rate   jsonb;
  v      integer;
  tid    integer;
  mins   integer;
  types  integer[];
  photo  text;
  max_items constant integer := 50;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'the payload must be an object' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) k
             where k <> all (array['display_name', 'headline', 'zone', 'practice_start_year', 'location_id', 'photo_path',
                                   'therapies', 'languages', 'service_modes', 'session_formats', 'contacts'])) then
    raise exception 'the payload has unknown keys' using errcode = '22023';
  end if;

  -- text scalars / escalares de texto
  if p_payload ? 'display_name' then
    if jsonb_typeof(p_payload -> 'display_name') not in ('string', 'null') then
      raise exception 'display_name must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set display_name = p_payload ->> 'display_name' where id = p_profile_id;
  end if;
  if p_payload ? 'headline' then
    if jsonb_typeof(p_payload -> 'headline') not in ('string', 'null') then
      raise exception 'headline must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set headline = p_payload ->> 'headline' where id = p_profile_id;
  end if;
  if p_payload ? 'zone' then
    if jsonb_typeof(p_payload -> 'zone') not in ('string', 'null') then
      raise exception 'zone must be text or null' using errcode = '22023';
    end if;
    update public.therapist_profiles set zone = p_payload ->> 'zone' where id = p_profile_id;
  end if;
  if p_payload ? 'photo_path' then
    if jsonb_typeof(p_payload -> 'photo_path') not in ('string', 'null') then
      raise exception 'photo_path must be text or null' using errcode = '22023';
    end if;
    photo := p_payload ->> 'photo_path';
    if photo is not null and (left(photo, 37) <> p_profile_id::text || '/'
                              or photo !~ '^[A-Za-z0-9/_.-]+$' or photo like '%..%') then
      raise exception 'photo_path must be a clean path under the profile folder' using errcode = '22023';
    end if;
    update public.therapist_profiles set photo_path = photo where id = p_profile_id;
  end if;

  -- numeric scalars / escalares numéricos
  if p_payload ? 'practice_start_year' then
    if jsonb_typeof(p_payload -> 'practice_start_year') = 'null' then
      update public.therapist_profiles set practice_start_year = null where id = p_profile_id;
    else
      update public.therapist_profiles
         set practice_start_year = public.revision_int(p_payload -> 'practice_start_year', 'practice_start_year')
       where id = p_profile_id;
    end if;
  end if;
  if p_payload ? 'location_id' then
    if jsonb_typeof(p_payload -> 'location_id') = 'null' then
      update public.therapist_profiles set location_id = null where id = p_profile_id;
    else
      v := public.revision_int(p_payload -> 'location_id', 'location_id');
      if not exists (select 1 from public.locations where id = v and is_active) then
        raise exception 'unknown or inactive location' using errcode = '22023';
      end if;
      update public.therapist_profiles set location_id = v where id = p_profile_id;  -- the guard requires a city
    end if;
  end if;

  -- simple lists / listas simples
  if p_payload ? 'languages' then
    if jsonb_typeof(p_payload -> 'languages') <> 'array' or jsonb_array_length(p_payload -> 'languages') > max_items then
      raise exception 'languages must be a list of at most % ids', max_items using errcode = '22023';
    end if;
    delete from public.profile_languages where profile_id = p_profile_id;
    for elem in select value from jsonb_array_elements(p_payload -> 'languages') loop
      v := public.revision_int(elem, 'language id');
      if not exists (select 1 from public.languages where id = v and is_active) then
        raise exception 'unknown or inactive language' using errcode = '22023';
      end if;
      insert into public.profile_languages (profile_id, language_id) values (p_profile_id, v);
    end loop;
  end if;
  if p_payload ? 'service_modes' then
    if jsonb_typeof(p_payload -> 'service_modes') <> 'array' or jsonb_array_length(p_payload -> 'service_modes') > max_items then
      raise exception 'service_modes must be a list of at most % ids', max_items using errcode = '22023';
    end if;
    delete from public.profile_service_modes where profile_id = p_profile_id;
    for elem in select value from jsonb_array_elements(p_payload -> 'service_modes') loop
      v := public.revision_int(elem, 'service mode id');
      if not exists (select 1 from public.service_modes where id = v and is_active) then
        raise exception 'unknown or inactive service mode' using errcode = '22023';
      end if;
      insert into public.profile_service_modes (profile_id, service_mode_id) values (p_profile_id, v);
    end loop;
  end if;
  if p_payload ? 'session_formats' then
    if jsonb_typeof(p_payload -> 'session_formats') <> 'array' or jsonb_array_length(p_payload -> 'session_formats') > max_items then
      raise exception 'session_formats must be a list of at most % ids', max_items using errcode = '22023';
    end if;
    delete from public.profile_session_formats where profile_id = p_profile_id;
    for elem in select value from jsonb_array_elements(p_payload -> 'session_formats') loop
      v := public.revision_int(elem, 'session format id');
      if not exists (select 1 from public.session_formats where id = v and is_active) then
        raise exception 'unknown or inactive session format' using errcode = '22023';
      end if;
      insert into public.profile_session_formats (profile_id, session_format_id) values (p_profile_id, v);
    end loop;
  end if;

  -- therapies with their rates (the limit and the currency rules are enforced by the table triggers)
  -- terapias con sus tarifas (el límite y las reglas de moneda las hacen los triggers de las tablas)
  if p_payload ? 'therapies' then
    if jsonb_typeof(p_payload -> 'therapies') <> 'array' or jsonb_array_length(p_payload -> 'therapies') > max_items then
      raise exception 'therapies must be a list' using errcode = '22023';
    end if;
    delete from public.profile_therapies where profile_id = p_profile_id;  -- rates go with them (cascade)
    for elem in select value from jsonb_array_elements(p_payload -> 'therapies') loop
      if jsonb_typeof(elem) <> 'object' then
        raise exception 'each therapy must be an object' using errcode = '22023';
      end if;
      tid := public.revision_int(elem -> 'therapy_id', 'therapy_id');
      if not exists (select 1 from public.therapies where id = tid and is_active) then
        raise exception 'unknown or inactive therapy' using errcode = '22023';
      end if;
      mins := case when jsonb_typeof(elem -> 'session_minutes') in ('number')
                   then public.revision_int(elem -> 'session_minutes', 'session_minutes') else null end;
      if elem ? 'session_minutes' and jsonb_typeof(elem -> 'session_minutes') not in ('number', 'null') then
        raise exception 'session_minutes must be a number or null' using errcode = '22023';
      end if;
      insert into public.profile_therapies (profile_id, therapy_id, session_minutes) values (p_profile_id, tid, mins);
      if elem ? 'rates' then
        if jsonb_typeof(elem -> 'rates') <> 'array' or jsonb_array_length(elem -> 'rates') > 10 then
          raise exception 'rates must be a list' using errcode = '22023';
        end if;
        for rate in select value from jsonb_array_elements(elem -> 'rates') loop
          if jsonb_typeof(rate) <> 'object' or jsonb_typeof(rate -> 'amount') <> 'number' then
            raise exception 'each rate needs rate_audience_id, amount and currency_id' using errcode = '22023';
          end if;
          if not exists (select 1 from public.rate_audiences
                         where id = public.revision_int(rate -> 'rate_audience_id', 'rate_audience_id') and is_active) then
            raise exception 'unknown or inactive rate audience' using errcode = '22023';
          end if;
          if not exists (select 1 from public.currencies
                         where id = public.revision_int(rate -> 'currency_id', 'currency_id') and is_active) then
            raise exception 'unknown or inactive currency' using errcode = '22023';
          end if;
          insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id)
            values (p_profile_id, tid, (rate ->> 'rate_audience_id')::smallint, (rate ->> 'amount')::numeric,
                    (rate ->> 'currency_id')::smallint);
        end loop;
      end if;
    end loop;
  end if;

  -- contacts: upsert the given ones, then remove the rest (a published profile cannot lose its phone)
  -- contactos: se guardan los dados y se quitan los demás (un perfil publicado no puede perder el teléfono)
  if p_payload ? 'contacts' then
    if jsonb_typeof(p_payload -> 'contacts') <> 'array' or jsonb_array_length(p_payload -> 'contacts') > 10 then
      raise exception 'contacts must be a list' using errcode = '22023';
    end if;
    types := '{}';
    for elem in select value from jsonb_array_elements(p_payload -> 'contacts') loop
      if jsonb_typeof(elem) <> 'object' or jsonb_typeof(elem -> 'value') <> 'string'
         or jsonb_typeof(coalesce(elem -> 'accepts_whatsapp', 'false'::jsonb)) <> 'boolean' then
        raise exception 'each contact needs contact_type_id, value and optionally accepts_whatsapp' using errcode = '22023';
      end if;
      v := public.revision_int(elem -> 'contact_type_id', 'contact_type_id');
      if not exists (select 1 from public.contact_types where id = v and is_active) then
        raise exception 'unknown or inactive contact type' using errcode = '22023';
      end if;
      types := types || v;
      insert into public.profile_contacts (profile_id, contact_type_id, value, accepts_whatsapp)
        values (p_profile_id, v, elem ->> 'value', coalesce((elem ->> 'accepts_whatsapp')::boolean, false))
        on conflict (profile_id, contact_type_id)
        do update set value = excluded.value, accepts_whatsapp = excluded.accepts_whatsapp;
    end loop;
    delete from public.profile_contacts where profile_id = p_profile_id and contact_type_id <> all (types);
  end if;
end
$$;
