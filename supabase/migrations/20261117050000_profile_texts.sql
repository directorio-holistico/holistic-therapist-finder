-- Two new profile texts: a short description per therapy (200 characters) and "Sobre mí" / about (1,500 characters).
-- SECURITY CHANGE: 2 columns (CHECKs), 2 column grants for anon, 2 functions, 1 view, 2 functions replaced. No new table.
-- Dos textos nuevos del perfil: una descripción corta por terapia (200 caracteres) y "Sobre mí" (1.500 caracteres).
-- CAMBIO DE SEGURIDAD: 2 columnas (con CHECK), 2 permisos de columna para anon, 2 funciones, 1 vista, 2 funciones reemplazadas.
-- Sin tablas nuevas.
--
--  * Same path as every other profile field: the therapist writes NOTHING live. Both texts travel inside a revision
--    (payload keys "about" and "description" inside each therapy), an admin approves it, and only then
--    apply_revision_payload writes them. The restricted-terms check already reads every string of the payload.
--    Mismo camino que el resto: el terapeuta no escribe nada vigente. Los textos viajan en una revisión y recién al
--    aprobarla apply_revision_payload los escribe. El control de términos restringidos ya lee todo texto del payload.
--  * NO contact data inside the texts (owner decision): a link, an e-mail, an @handle or a long phone number would skip
--    the contact reveal (Turnstile, daily limit, log). contains_contact_data() is checked by the CHECK constraints AND when a
--    revision is submitted, so the therapist sees the error right away. Websites and social networks have their own contact fields.
--    Sin datos de contacto dentro de los textos: un enlace, un mail, un @usuario o un teléfono largo se saltearía el
--    "mostrar contacto" (Turnstile, límite diario, registro). Lo revisan los CHECK y el envío de la revisión.
--  * Visitors: anon gets SELECT on the two columns, only for published profiles (the existing row policies apply).
--    Visitantes: anon lee las dos columnas, solo de perfiles publicados (valen las políticas de fila existentes).
--  * "about" is shown only in the full profile, not in the search card: it is added at the END of public_profile_detail;
--    public_profile_cards does not change. / "about" solo en el perfil completo: va AL FINAL de public_profile_detail.
--  * public_profile_detail is rebuilt with its columns listed one by one (c.* would now also pull the card column
--    therapy_short_names into the middle and break CREATE OR REPLACE VIEW).
--    La vista de detalle se rearma con las columnas una por una (c.* arrastraría therapy_short_names al medio).

-- ============================================================================
-- 1. Helper: contact data inside a free text / Ayuda: datos de contacto dentro de un texto libre
-- ============================================================================
create function public.contains_contact_data(p_text text)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select p_text ~* '(https?:|www\.|\mwa\.me|\m[[:alnum:]-]+\.(com|net|org|info|ar|cl|mx|es|io|me|co|app|link|bio|site|online|ly)(\M|/))'
      or p_text ~ '@[[:alnum:]_.]{3,}'
      or p_text ~ '(\d[ .()-]*){9,}'
$$;
-- pure text function, no data access: the CHECKs run it with the writer role, so the API roles keep EXECUTE
-- función de texto pura, sin acceso a datos: los CHECK la corren con el rol que escribe
revoke execute on function public.contains_contact_data(text) from public, anon;
grant execute on function public.contains_contact_data(text) to authenticated, service_role;

-- ============================================================================
-- 2. Columns / Columnas
-- ============================================================================
alter table public.therapist_profiles
  add column about text
  check (about = btrim(about) and char_length(about) between 1 and 1500 and not public.contains_contact_data(about));
comment on column public.therapist_profiles.about is
  '"Sobre mí": longer presentation, full profile only, no contact data / Presentación larga, solo en el perfil completo, sin datos de contacto.';

alter table public.profile_therapies
  add column description text
  check (description = btrim(description) and char_length(description) between 1 and 200 and not public.contains_contact_data(description));
comment on column public.profile_therapies.description is
  'Short description of how the therapist practices this therapy (type, training) / Descripción corta de cómo practica esta terapia.';

grant select (about) on public.therapist_profiles to anon;
grant select (description) on public.profile_therapies to anon;

-- ============================================================================
-- 3. Validation of the two texts inside a payload / Validación de los dos textos dentro de un payload
-- ============================================================================
create function public.validate_profile_texts(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  t    text;
  elem jsonb;
begin
  if p_payload ? 'about' then
    if jsonb_typeof(p_payload -> 'about') not in ('string', 'null') then
      raise exception 'about must be text or null' using errcode = '22023';
    end if;
    t := btrim(p_payload ->> 'about');
    if char_length(t) > 1500 then
      raise exception 'about is longer than 1500 characters' using errcode = '22023';
    end if;
    if public.contains_contact_data(t) then
      raise exception 'about cannot contain links, e-mails, @handles or phone numbers' using errcode = '22023';
    end if;
  end if;
  if jsonb_typeof(p_payload -> 'therapies') = 'array' then
    for elem in select value from jsonb_array_elements(p_payload -> 'therapies') loop
      if jsonb_typeof(elem) = 'object' and elem ? 'description' then
        if jsonb_typeof(elem -> 'description') not in ('string', 'null') then
          raise exception 'description must be text or null' using errcode = '22023';
        end if;
        t := btrim(elem ->> 'description');
        if char_length(t) > 200 then
          raise exception 'a therapy description is longer than 200 characters' using errcode = '22023';
        end if;
        if public.contains_contact_data(t) then
          raise exception 'a therapy description cannot contain links, e-mails, @handles or phone numbers' using errcode = '22023';
        end if;
      end if;
    end loop;
  end if;
end
$$;
revoke execute on function public.validate_profile_texts(jsonb) from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. Public detail view: "about" at the END, "description" inside each therapy of "therapies_detail"
--    Vista pública de detalle: "about" AL FINAL, "description" dentro de cada terapia de "therapies_detail"
-- ============================================================================
create or replace view public.public_profile_detail with (security_invoker = true) as
SELECT c.profile_id,
    c.display_name,
    c.photo_path,
    c.headline,
    c.zone,
    c.approved_at,
    c.city_id,
    c.city_name,
    c.region_id,
    c.region_name,
    c.country_id,
    c.country_name,
    c.country_iso,
    c.therapy_ids,
    c.therapy_names,
    c.service_modes,
    c.session_formats,
    c.languages,
    c.rates_from,
    c.rates_confirmed_at,
    c.rates_current,
    c.is_pinned,
    tp.practice_start_year,
    ( SELECT pc.value
           FROM public.profile_contacts pc
          WHERE pc.profile_id = c.profile_id AND public.public_contact_code(pc.contact_type_id) = 'website'::text) AS website,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('therapy_id', t.id, 'name', COALESCE(tt.name, t.code), 'session_minutes', pt.session_minutes, 'description', pt.description, 'service_modes', COALESCE(( SELECT jsonb_agg(m.code ORDER BY m.sort_order, m.id) AS jsonb_agg
                   FROM public.profile_therapy_service_modes x
                     JOIN public.service_modes m ON m.id = x.service_mode_id AND m.is_active
                  WHERE x.profile_id = pt.profile_id AND x.therapy_id = pt.therapy_id), '[]'::jsonb), 'session_formats', COALESCE(( SELECT jsonb_agg(f.code ORDER BY f.sort_order, f.id) AS jsonb_agg
                   FROM public.profile_therapy_session_formats x
                     JOIN public.session_formats f ON f.id = x.session_format_id AND f.is_active
                  WHERE x.profile_id = pt.profile_id AND x.therapy_id = pt.therapy_id), '[]'::jsonb), 'rates', COALESCE(( SELECT jsonb_agg(jsonb_build_object('audience', a.code, 'amount', r.amount, 'currency', cu.code) ORDER BY a.sort_order, a.id) AS jsonb_agg
                   FROM public.profile_therapy_rates r
                     JOIN public.rate_audiences a ON a.id = r.rate_audience_id AND a.is_active
                     JOIN public.currencies cu ON cu.id = r.currency_id
                  WHERE r.profile_id = pt.profile_id AND r.therapy_id = pt.therapy_id), '[]'::jsonb)) ORDER BY t.id) AS jsonb_agg
           FROM public.profile_therapies pt
             JOIN public.therapies t ON t.id = pt.therapy_id AND t.is_active
             LEFT JOIN public.therapy_translations tt ON tt.therapy_id = t.id AND tt.language_id = (( SELECT l.id
                   FROM public.languages l
                  WHERE l.code = 'es'::text))
          WHERE pt.profile_id = c.profile_id), '[]'::jsonb) AS therapies_detail,
    ( SELECT pc.value
           FROM public.profile_contacts pc
          WHERE pc.profile_id = c.profile_id AND public.public_contact_code(pc.contact_type_id) = 'instagram'::text) AS instagram,
    ( SELECT pc.value
           FROM public.profile_contacts pc
          WHERE pc.profile_id = c.profile_id AND public.public_contact_code(pc.contact_type_id) = 'facebook'::text) AS facebook,
    ( SELECT pc.value
           FROM public.profile_contacts pc
          WHERE pc.profile_id = c.profile_id AND public.public_contact_code(pc.contact_type_id) = 'tiktok'::text) AS tiktok,
    ( SELECT pc.value
           FROM public.profile_contacts pc
          WHERE pc.profile_id = c.profile_id AND public.public_contact_code(pc.contact_type_id) = 'youtube'::text) AS youtube,
    tp.about
   FROM public.public_profile_cards c
     JOIN public.therapist_profiles tp ON tp.id = c.profile_id;

comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';

-- ============================================================================
-- 5. Functions replaced (same signatures, so permissions are kept)
--    Funciones reemplazadas (mismas firmas, así que se conservan los permisos)
-- ============================================================================
-- submit_revision: new allowed key "about" + early validation of both texts.
-- submit_revision: clave nueva "about" + validación temprana de los dos textos.
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
                                          'photo_path', 'about', 'therapies', 'languages', 'contacts'];
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

  -- the new texts ("about", each therapy "description") are checked here too, so the therapist gets the error when sending
  -- los textos nuevos ("about", "description" de cada terapia) se validan también acá: el error le llega al enviar
  perform public.validate_profile_texts(rev.payload);

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

-- apply_revision_payload: writes "about" and the "description" of each therapy.
-- apply_revision_payload: escribe "about" y la "description" de cada terapia.
create or replace function public.apply_revision_payload(p_profile_id uuid, p_payload jsonb)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  elem   jsonb;
  opt    jsonb;
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
                                   'about', 'therapies', 'languages', 'contacts'])) then
    raise exception 'the payload has unknown keys' using errcode = '22023';
  end if;

  perform public.validate_profile_texts(p_payload);

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
  if p_payload ? 'about' then
    update public.therapist_profiles set about = nullif(btrim(p_payload ->> 'about'), '') where id = p_profile_id;
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
      insert into public.profile_therapies (profile_id, therapy_id, session_minutes, description)
        values (p_profile_id, tid, mins, nullif(btrim(elem ->> 'description'), ''));
      -- service modes and session formats of THIS therapy: each list is required and has at least one item
      -- modalidades y formatos de sesión de ESTA terapia: cada lista es obligatoria y tiene al menos un elemento
      if jsonb_typeof(elem -> 'service_modes') is distinct from 'array' or jsonb_array_length(elem -> 'service_modes') not between 1 and 10 then
        raise exception 'each therapy needs a list of 1 to 10 service modes' using errcode = '22023';
      end if;
      for opt in select value from jsonb_array_elements(elem -> 'service_modes') loop
        v := public.revision_int(opt, 'service mode id');
        if not exists (select 1 from public.service_modes where id = v and is_active) then
          raise exception 'unknown or inactive service mode' using errcode = '22023';
        end if;
        insert into public.profile_therapy_service_modes (profile_id, therapy_id, service_mode_id)
          values (p_profile_id, tid, v) on conflict do nothing;
      end loop;
      if jsonb_typeof(elem -> 'session_formats') is distinct from 'array' or jsonb_array_length(elem -> 'session_formats') not between 1 and 10 then
        raise exception 'each therapy needs a list of 1 to 10 session formats' using errcode = '22023';
      end if;
      for opt in select value from jsonb_array_elements(elem -> 'session_formats') loop
        v := public.revision_int(opt, 'session format id');
        if not exists (select 1 from public.session_formats where id = v and is_active) then
          raise exception 'unknown or inactive session format' using errcode = '22023';
        end if;
        insert into public.profile_therapy_session_formats (profile_id, therapy_id, session_format_id)
          values (p_profile_id, tid, v) on conflict do nothing;
      end loop;
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
  -- The payload carried the therapies WITH their rates: the admin approves those rates, so they count as confirmed now.
  -- El payload trajo las terapias CON sus tarifas: el admin aprueba esas tarifas, así que cuentan como confirmadas hoy.
  if p_payload ? 'therapies' then
    update public.therapist_profiles set rates_confirmed_at = now() where id = p_profile_id;
  end if;

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
