-- Approving and rejecting revisions (administrator side). SECURITY CHANGE: 2 callable admin functions, 3 internal ones, 1 setting.
-- Aprobar y rechazar revisiones (lado del administrador). CAMBIO DE SEGURIDAD: 2 funciones de admin, 3 internas, 1 ajuste.
--
-- Rules applied / Reglas aplicadas:
--  * The live profile changes ONLY here, when an admin approves a pending revision. Everything happens in one
--    transaction: if any part of the payload is invalid, nothing is applied.
--    El perfil vigente cambia SOLO acá, cuando un admin aprueba una revisión pendiente. Todo ocurre en una sola
--    transacción: si una parte del contenido es inválida, no se aplica nada.
--  * Payload semantics: a key that is present REPLACES that part of the profile; a key that is absent leaves it
--    unchanged. Scalars may be null (clears the value). Lists replace the whole list. "therapies" carries its own
--    rates, so replacing therapies replaces their rates.
--    Semántica: una clave presente REEMPLAZA esa parte del perfil; una ausente la deja igual. Los escalares pueden
--    ser null (borra el valor). Las listas reemplazan la lista entera. "therapies" lleva sus tarifas.
--  * Payload shape / Forma del contenido:
--      headline, zone, photo_path: text | null     practice_start_year, location_id: whole number | null
--      languages, service_modes, session_formats: [id, ...]
--      therapies: [{therapy_id, session_minutes?, rates?: [{rate_audience_id, amount, currency_id}]}]
--      contacts:  [{contact_type_id, value, accepts_whatsapp?}]
--  * Every referenced catalog row must exist and be active. A photo path must live under the profile's own folder.
--    Toda fila de catálogo referenciada debe existir y estar activa. La foto debe estar en la carpeta del propio perfil.
--  * First approval of an unpublished profile publishes it and sets approved_at. A paused profile stays paused.
--    Suspended or erased profiles cannot be approved.
--    La primera aprobación de un perfil sin publicar lo publica y fija approved_at. Uno pausado sigue pausado.
--  * An admin cannot approve their own profile's revision unless the setting moderation_allow_self_approval is true.
--    Un admin no aprueba revisiones de su propio perfil salvo que moderation_allow_self_approval sea true.
--  * Identity comes only from auth.uid(); every decision writes a moderation_events row.
--    La identidad sale solo de auth.uid(); toda decisión escribe una fila en moderation_events.

-- ============================================================================
-- 1. Setting / Ajuste
-- ============================================================================
alter table public.app_settings drop constraint app_settings_value_valid;
alter table public.app_settings add constraint app_settings_value_valid check (
  case key
    when 'max_therapies_per_profile'
      then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
    when 'review_days_initial' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_update' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_priority' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'moderation_allow_self_approval' then jsonb_typeof(value) = 'boolean'
    else true
  end);

insert into public.app_settings (key, value, is_public, description) values
  ('moderation_allow_self_approval', 'false', false,
   'Allow an admin to approve revisions of their own profile (true/false) / Permitir que un admin apruebe revisiones de su propio perfil (true/false)');

-- ============================================================================
-- 2. Internal helpers (nobody calls them through the API) / Auxiliares internas
-- ============================================================================

-- revision_int: a non-negative whole number inside a JSON value, or a clear error.
-- revision_int: un entero no negativo dentro de un JSON, o un error claro.
create function public.revision_int(v jsonb, label text)
returns integer
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  if v is null or jsonb_typeof(v) <> 'number' or v::text !~ '^[0-9]{1,9}$' then
    raise exception '% must be a whole number', label using errcode = '22023';
  end if;
  return (v::text)::integer;
end
$$;
revoke execute on function public.revision_int(jsonb, text) from public, anon, authenticated, service_role;

-- apply_revision_payload: validates the payload completely and writes it to the live profile tables.
-- apply_revision_payload: valida el contenido por completo y lo escribe en las tablas del perfil vigente.
create function public.apply_revision_payload(p_profile_id uuid, p_payload jsonb)
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
             where k <> all (array['headline', 'zone', 'practice_start_year', 'location_id', 'photo_path',
                                   'therapies', 'languages', 'service_modes', 'session_formats', 'contacts'])) then
    raise exception 'the payload has unknown keys' using errcode = '22023';
  end if;

  -- text scalars / escalares de texto
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
revoke execute on function public.apply_revision_payload(uuid, jsonb) from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. approve_revision / reject_revision (admin only)
-- ============================================================================

create function public.approve_revision(p_revision_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor        uuid := public.current_person_id();
  rev          public.profile_revisions%rowtype;
  prof         public.therapist_profiles%rowtype;
  current_code text;
  profile_code text;
  published_id smallint;
  new_profile_status smallint;
  self_ok      boolean;
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;

  select * into rev from public.profile_revisions where id = p_revision_id for update;
  if not found then
    raise exception 'revision not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.revision_statuses where id = rev.status_id;
  if current_code <> 'pending_review' then
    raise exception 'only a pending revision can be approved' using errcode = '55000';
  end if;

  select * into prof from public.therapist_profiles where id = rev.profile_id for update;
  select code into strict profile_code from public.profile_statuses where id = prof.status_id;
  if profile_code in ('suspended', 'erased') then
    raise exception 'a % profile cannot be approved', profile_code using errcode = '55000';
  end if;

  select coalesce((value = 'true'::jsonb), false) into self_ok
    from public.app_settings where key = 'moderation_allow_self_approval';
  if prof.person_id = actor and not coalesce(self_ok, false) then
    raise exception 'you cannot approve a revision of your own profile' using errcode = '42501';
  end if;

  perform public.apply_revision_payload(prof.id, rev.payload);

  -- first approval of an unpublished profile publishes it / la primera aprobación de un perfil sin publicar lo publica
  if profile_code = 'unpublished' then
    select id into strict published_id from public.profile_statuses where code = 'published';
    new_profile_status := published_id;
  end if;
  update public.therapist_profiles
     set approved_at = coalesce(approved_at, now()),
         status_id = coalesce(new_profile_status, status_id)
   where id = prof.id;

  update public.profile_revisions
     set status_id = (select id from public.revision_statuses where code = 'approved'),
         decided_at = now(),
         closed_at = now()
   where id = rev.id;

  insert into public.moderation_events (profile_id, revision_id, actor_person_id, revision_status_id, profile_status_id)
    values (prof.id, rev.id, actor, (select id from public.revision_statuses where code = 'approved'), new_profile_status);
end
$$;
revoke execute on function public.approve_revision(uuid) from public, anon, service_role;
grant execute on function public.approve_revision(uuid) to authenticated;

create function public.reject_revision(p_revision_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor        uuid := public.current_person_id();
  rev          public.profile_revisions%rowtype;
  current_code text;
  reason       text := btrim(p_reason);
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if reason is null or char_length(reason) not between 1 and 1000 then
    raise exception 'a rejection needs a reason (1-1000 characters)' using errcode = '22023';
  end if;

  select * into rev from public.profile_revisions where id = p_revision_id for update;
  if not found then
    raise exception 'revision not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.revision_statuses where id = rev.status_id;
  if current_code <> 'pending_review' then
    raise exception 'only a pending revision can be rejected' using errcode = '55000';
  end if;

  update public.profile_revisions
     set status_id = (select id from public.revision_statuses where code = 'rejected'),
         rejection_reason = reason,
         decided_at = now(),
         closed_at = now()
   where id = rev.id;

  insert into public.moderation_events (profile_id, revision_id, actor_person_id, revision_status_id, reason)
    values (rev.profile_id, rev.id, actor, (select id from public.revision_statuses where code = 'rejected'), reason);
end
$$;
revoke execute on function public.reject_revision(uuid, text) from public, anon, service_role;
grant execute on function public.reject_revision(uuid, text) to authenticated;
