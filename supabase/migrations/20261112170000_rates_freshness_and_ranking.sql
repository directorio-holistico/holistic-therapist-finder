-- Rates freshness, owner pin and new result order. SECURITY CHANGE: 2 columns, 3 functions callable by logged-in users,
-- 1 helper callable by visitors, replaced guard/search/views.
-- Frescura de tarifas, perfil fijado del dueño y nuevo orden de resultados. CAMBIO DE SEGURIDAD: 2 columnas, 3 funciones
-- para usuarios con sesión, 1 ayuda para visitantes, guarda/búsqueda/vistas reemplazadas.
--
-- Rules applied (owner decisions of 12/11/2026) / Reglas aplicadas (decisiones del titular del 12/11/2026):
--  * Rates have a confirmation date (therapist_profiles.rates_confirmed_at). They are "current" while the date is within
--    rates_validity_months (6 by default, configurable 1-36). A profile with no rates is never "current".
--    Las tarifas tienen fecha de confirmación. Están "al día" mientras la fecha entre en rates_validity_months (6 por
--    defecto, configurable 1-36). Un perfil sin tarifas nunca está "al día".
--  * The therapist changes or confirms rates WITHOUT moderation (update_my_rates / confirm_my_rates): they are numbers
--    plus a catalog currency, so they cannot carry a cure claim. Contacts still go through a revision (admin writes to the
--    new phone or mail to check it).
--    El terapeuta cambia o confirma sus tarifas SIN moderación: son números y una moneda del catálogo, no pueden llevar
--    una promesa de cura. Los contactos siguen por revisión (el admin escribe al teléfono o mail nuevo para comprobarlo).
--  * Approving a revision that carries therapies (with their rates) also confirms the rates as of now.
--    Aprobar una revisión que trae terapias (con sus tarifas) también confirma las tarifas a la fecha.
--  * Result order inside each group: pinned profile, current rates, photo, oldest approval, id. The pin is a privilege field
--    only an admin can change (set_profile_pinned); the UI shows a discreet "Fundador del sitio" legend. It is NOT a paid
--    feature. No new table.
--    Orden dentro de cada grupo: perfil fijado, tarifas al día, foto, aprobación más antigua, id. El fijado es un campo
--    de privilegio que solo cambia un admin (set_profile_pinned); la interfaz muestra la leyenda discreta "Fundador del
--    sitio". NO es una función paga. Sin tablas nuevas.
--  * Visitors can read the two new columns (they are shown on public cards); person_id and the other private columns stay hidden.
--    Los visitantes leen las dos columnas nuevas (se muestran en las tarjetas); person_id y las demás privadas siguen ocultas.

-- ============================================================================
-- 1. Columns and setting / Columnas y ajuste
-- ============================================================================
alter table public.therapist_profiles
  add column rates_confirmed_at timestamptz,
  add column is_pinned boolean not null default false;
comment on column public.therapist_profiles.rates_confirmed_at is
  'When the therapist (or an approved revision) last confirmed the rates; null = never / Cuándo se confirmaron las tarifas por última vez; nulo = nunca.';
comment on column public.therapist_profiles.is_pinned is
  'Site-owner pin: shown first inside its result group, with a legend. Admin only, never paid / Fijado del dueño del sitio: va primero dentro de su grupo, con leyenda. Solo admin, nunca pago.';

alter table public.app_settings drop constraint app_settings_value_valid;
alter table public.app_settings add constraint app_settings_value_valid check (
  case key
    when 'max_therapies_per_profile'
      then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
    when 'review_days_initial' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_update' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_priority' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'moderation_allow_self_approval' then jsonb_typeof(value) = 'boolean'
    when 'retention_unmet_searches_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_contact_reveals_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_reports_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_erasure_fingerprints_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'reveal_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,5}$' and (value::text)::int between 1 and 10000
    when 'retention_rate_limit_days' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'retention_audit_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'rates_validity_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 36
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('rates_validity_months', '6', true,
   'Months a rate confirmation stays current (1-36) / Meses que una confirmación de tarifas se considera al día (1-36)');

-- Visitors read the two new columns through the public views (security invoker). person_id, status and the rest stay hidden.
-- Los visitantes leen las dos columnas nuevas por las vistas públicas. person_id, estado y el resto siguen ocultos.
grant select (rates_confirmed_at, is_pinned) on public.therapist_profiles to anon;

-- Validity of a rate confirmation, readable by visitors without opening app_settings (same pattern as is_published_profile).
-- Vigencia de una confirmación de tarifas, legible por visitantes sin abrir app_settings (mismo patrón que is_published_profile).
create function public.rates_validity_months()
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((select (s.value::text)::integer from public.app_settings s
                    where s.key = 'rates_validity_months' and jsonb_typeof(s.value) = 'number'), 6)
$$;
revoke execute on function public.rates_validity_months() from public, service_role;
grant execute on function public.rates_validity_months() to anon, authenticated;

-- ============================================================================
-- 2. Guard: the two new columns are privilege fields / La guarda: las dos columnas nuevas son campos de privilegio
-- ============================================================================
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
       or new.status_reason is distinct from old.status_reason
       or new.is_pinned is distinct from old.is_pinned
       or new.rates_confirmed_at is distinct from old.rates_confirmed_at then
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

-- ============================================================================
-- 3. Approving a revision with therapies confirms the rates / Aprobar una revisión con terapias confirma las tarifas
-- ============================================================================
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

-- ============================================================================
-- 4. Functions for logged-in users / Funciones para usuarios con sesión
-- ============================================================================

-- update_my_rates: the therapist replaces ALL the rates of their own published profile, with no moderation.
-- Only therapies already in the profile, active audiences and currencies, amounts 0..9999999999.99. All or nothing.
-- update_my_rates: el terapeuta reemplaza TODAS las tarifas de su propio perfil publicado, sin moderación.
-- Solo terapias que ya están en el perfil, audiencias y monedas activas, montos 0..9999999999,99. Todo o nada.
create function public.update_my_rates(p_rates jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor    uuid := public.current_person_id();
  prof     public.therapist_profiles%rowtype;
  pstatus  text;
  elem     jsonb;
  tid      integer;
  aud      integer;
  cur      integer;
  amt      numeric;
  minor    smallint;
begin
  if actor is null then
    raise exception 'sign in as a therapist first' using errcode = '42501';
  end if;
  select * into prof from public.therapist_profiles where person_id = actor for update;
  if not found then
    raise exception 'you have no profile' using errcode = 'P0002';
  end if;
  select code into strict pstatus from public.profile_statuses where id = prof.status_id;
  if pstatus <> 'published' then
    raise exception 'rates change directly only on a published profile; use a revision' using errcode = '55000';
  end if;
  if p_rates is null or jsonb_typeof(p_rates) <> 'array' or jsonb_array_length(p_rates) > 40 then
    raise exception 'rates must be a list of at most 40 items' using errcode = '22023';
  end if;

  -- validate everything before touching anything / validar todo antes de tocar nada
  for elem in select value from jsonb_array_elements(p_rates) loop
    if jsonb_typeof(elem) <> 'object'
       or exists (select 1 from jsonb_object_keys(elem) k
                   where k <> all (array['therapy_id', 'rate_audience_id', 'amount', 'currency_id'])) then
      raise exception 'each rate needs therapy_id, rate_audience_id, amount and currency_id only' using errcode = '22023';
    end if;
    tid := public.revision_int(elem -> 'therapy_id', 'therapy_id');
    aud := public.revision_int(elem -> 'rate_audience_id', 'rate_audience_id');
    cur := public.revision_int(elem -> 'currency_id', 'currency_id');
    if jsonb_typeof(elem -> 'amount') <> 'number' then
      raise exception 'amount must be a number' using errcode = '22023';
    end if;
    amt := (elem ->> 'amount')::numeric;
    if amt < 0 or amt > 9999999999.99 then
      raise exception 'amount out of range' using errcode = '22023';
    end if;
    if not exists (select 1 from public.profile_therapies where profile_id = prof.id and therapy_id = tid) then
      raise exception 'the therapy is not in your profile' using errcode = '22023';
    end if;
    if not exists (select 1 from public.rate_audiences where id = aud and is_active) then
      raise exception 'unknown or inactive rate audience' using errcode = '22023';
    end if;
    select c.minor_units into minor from public.currencies c where c.id = cur and c.is_active;
    if not found then
      raise exception 'unknown or inactive currency' using errcode = '22023';
    end if;
    -- checked here because the column type would silently round 1.234 to 1.23 before the rates guard runs
    -- se controla acá porque el tipo de la columna redondearía 1,234 a 1,23 en silencio antes de la guarda de tarifas
    if amt <> round(amt, minor) then
      raise exception 'amount has more decimals than the currency allows' using errcode = '22023';
    end if;
  end loop;

  delete from public.profile_therapy_rates where profile_id = prof.id;
  for elem in select value from jsonb_array_elements(p_rates) loop
    insert into public.profile_therapy_rates (profile_id, therapy_id, rate_audience_id, amount, currency_id)
      values (prof.id, (elem ->> 'therapy_id')::integer, (elem ->> 'rate_audience_id')::smallint,
              (elem ->> 'amount')::numeric, (elem ->> 'currency_id')::smallint);  -- the rates guard checks decimals and one currency per audience
  end loop;
  update public.therapist_profiles set rates_confirmed_at = now() where id = prof.id;
end
$$;
revoke execute on function public.update_my_rates(jsonb) from public, anon, service_role;
grant execute on function public.update_my_rates(jsonb) to authenticated;

-- confirm_my_rates: "my rates are still current" in one tap; needs at least one rate.
-- confirm_my_rates: "mis precios siguen vigentes" en un toque; exige al menos una tarifa.
create function public.confirm_my_rates()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor   uuid := public.current_person_id();
  prof    public.therapist_profiles%rowtype;
  pstatus text;
begin
  if actor is null then
    raise exception 'sign in as a therapist first' using errcode = '42501';
  end if;
  select * into prof from public.therapist_profiles where person_id = actor for update;
  if not found then
    raise exception 'you have no profile' using errcode = 'P0002';
  end if;
  select code into strict pstatus from public.profile_statuses where id = prof.status_id;
  if pstatus <> 'published' then
    raise exception 'only a published profile can confirm rates' using errcode = '55000';
  end if;
  if not exists (select 1 from public.profile_therapy_rates where profile_id = prof.id) then
    raise exception 'there are no rates to confirm' using errcode = '55000';
  end if;
  update public.therapist_profiles set rates_confirmed_at = now() where id = prof.id;
end
$$;
revoke execute on function public.confirm_my_rates() from public, anon, service_role;
grant execute on function public.confirm_my_rates() to authenticated;

-- set_profile_pinned: admin only. The change is recorded by the audit trigger of therapist_profiles (column names only).
-- set_profile_pinned: solo admin. El cambio queda en el trigger de auditoría de therapist_profiles (solo nombres de columnas).
create function public.set_profile_pinned(p_profile_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.current_person_id() is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if p_pinned is null then
    raise exception 'pinned must be true or false' using errcode = '22023';
  end if;
  update public.therapist_profiles set is_pinned = p_pinned where id = p_profile_id;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
end
$$;
revoke execute on function public.set_profile_pinned(uuid, boolean) from public, anon, service_role;
grant execute on function public.set_profile_pinned(uuid, boolean) to authenticated;

-- ============================================================================
-- 5. Public views and search (columns added, new order) / Vistas públicas y búsqueda (columnas nuevas, nuevo orden)
-- ============================================================================
create or replace view public.public_profile_cards with (security_invoker = true) as
select
  tp.id                      as profile_id,
  tp.display_name,
  tp.photo_path,
  tp.headline,
  tp.zone,
  tp.approved_at,
  tp.location_id             as city_id,
  city_t.name                as city_name,
  anc.region_id,
  region_t.name              as region_name,
  anc.country_id,
  country_t.name             as country_name,
  country.iso_code           as country_iso,
  coalesce(th.therapy_ids, '{}')    as therapy_ids,
  coalesce(th.therapy_names, '{}')  as therapy_names,
  coalesce(sm.codes, '{}')   as service_modes,
  coalesce(sf.codes, '{}')   as session_formats,
  coalesce(lg.codes, '{}')   as languages,
  coalesce(rt.rates_from, '{}'::jsonb) as rates_from,
  -- new columns go at the END (create or replace view cannot insert columns in the middle)
  -- las columnas nuevas van AL FINAL (create or replace view no permite insertar columnas en el medio)
  tp.rates_confirmed_at,
  (rt.rates_from is not null and rt.rates_from <> '{}'::jsonb
   and tp.rates_confirmed_at is not null
   and tp.rates_confirmed_at >= now() - make_interval(months => public.rates_validity_months())) as rates_current,
  tp.is_pinned
from public.therapist_profiles tp
cross join lateral (select l.id from public.languages l where l.code = 'es') es
left join lateral (
  with recursive up as (
    select l.id, l.parent_id, l.level_id from public.locations l where l.id = tp.location_id
    union all
    select l.id, l.parent_id, l.level_id from public.locations l join up on l.id = up.parent_id
  )
  select max(up.id) filter (where ll.code = 'region')  as region_id,
         max(up.id) filter (where ll.code = 'country') as country_id
  from up join public.location_levels ll on ll.id = up.level_id
) anc on true
left join public.location_translations city_t on city_t.location_id = tp.location_id and city_t.language_id = es.id
left join public.location_translations region_t on region_t.location_id = anc.region_id and region_t.language_id = es.id
left join public.locations country on country.id = anc.country_id
left join public.location_translations country_t on country_t.location_id = anc.country_id and country_t.language_id = es.id
left join lateral (
  select array_agg(t.id order by t.id) as therapy_ids, array_agg(coalesce(tt.name, t.code) order by t.id) as therapy_names
  from public.profile_therapies pt
  join public.therapies t on t.id = pt.therapy_id and t.is_active
  left join public.therapy_translations tt on tt.therapy_id = t.id and tt.language_id = es.id
  where pt.profile_id = tp.id
) th on true
left join lateral (
  select array_agg(m.code order by m.sort_order, m.id) as codes
  from public.profile_service_modes x join public.service_modes m on m.id = x.service_mode_id and m.is_active
  where x.profile_id = tp.id
) sm on true
left join lateral (
  select array_agg(f.code order by f.sort_order, f.id) as codes
  from public.profile_session_formats x join public.session_formats f on f.id = x.session_format_id and f.is_active
  where x.profile_id = tp.id
) sf on true
left join lateral (
  select array_agg(l.code order by l.sort_order, l.id) as codes
  from public.profile_languages x join public.languages l on l.id = x.language_id and l.is_active
  where x.profile_id = tp.id
) lg on true
left join lateral (
  -- "from" rate per audience: the lowest amount, with its currency (one currency per audience in a profile)
  -- tarifa "desde" por audiencia: el monto más bajo, con su moneda (una moneda por audiencia en el perfil)
  select jsonb_object_agg(x.audience, jsonb_build_object('amount', x.min_amount, 'currency', x.currency)) as rates_from
  from (
    select a.code as audience, c.code as currency, min(r.amount) as min_amount
    from public.profile_therapy_rates r
    join public.therapies t on t.id = r.therapy_id and t.is_active
    join public.rate_audiences a on a.id = r.rate_audience_id and a.is_active
    join public.currencies c on c.id = r.currency_id
    where r.profile_id = tp.id
    group by a.code, c.code
  ) x
) rt on true
where public.is_published_profile(tp.id);

-- The detail view expands c.* so it is recreated (columns cannot be inserted in the middle of a view).
-- La vista de detalle expande c.* por eso se recrea (no se pueden insertar columnas en el medio de una vista).
drop view public.public_profile_detail;
create view public.public_profile_detail with (security_invoker = true) as
select
  c.*,
  tp.practice_start_year,
  (select pc.value from public.profile_contacts pc
    where pc.profile_id = c.profile_id and public.public_contact_code(pc.contact_type_id) = 'website') as website,
  coalesce((
    select jsonb_agg(jsonb_build_object(
             'therapy_id', t.id,
             'name', coalesce(tt.name, t.code),
             'session_minutes', pt.session_minutes,
             'rates', coalesce((
               select jsonb_agg(jsonb_build_object('audience', a.code, 'amount', r.amount, 'currency', cu.code) order by a.sort_order, a.id)
               from public.profile_therapy_rates r
               join public.rate_audiences a on a.id = r.rate_audience_id and a.is_active
               join public.currencies cu on cu.id = r.currency_id
               where r.profile_id = pt.profile_id and r.therapy_id = pt.therapy_id), '[]'::jsonb))
           order by t.id)
    from public.profile_therapies pt
    join public.therapies t on t.id = pt.therapy_id and t.is_active
    left join public.therapy_translations tt on tt.therapy_id = t.id and tt.language_id = (select l.id from public.languages l where l.code = 'es')
    where pt.profile_id = c.profile_id), '[]'::jsonb) as therapies_detail
from public.public_profile_cards c
join public.therapist_profiles tp on tp.id = c.profile_id;
comment on view public.public_profile_cards is 'Search result card of a published profile; no phone, no email / Tarjeta de resultado de un perfil publicado; sin teléfono ni mail.';
comment on view public.public_profile_detail is 'Public profile page; no phone, no email / Página pública del perfil; sin teléfono ni mail.';
grant select on public.public_profile_cards, public.public_profile_detail to anon, authenticated;

-- search_profiles changes its result columns, so it is dropped and created again (same signature, same permissions).
-- search_profiles cambia sus columnas de resultado, por eso se elimina y se crea de nuevo (misma firma, mismos permisos).
drop function public.search_profiles(integer, integer, text, integer, integer);
create function public.search_profiles(
  p_therapy_id   integer,
  p_location_id  integer,
  p_service_mode text    default null,
  p_limit        integer default 20,
  p_offset       integer default 0)
returns table (
  result_group smallint, total_count bigint,
  profile_id uuid, display_name text, photo_path text, headline text, zone text, approved_at timestamptz,
  city_id integer, city_name text, region_id integer, region_name text, country_id integer, country_name text, country_iso text,
  therapy_ids integer[], therapy_names text[], service_modes text[], session_formats text[], languages text[], rates_from jsonb,
  rates_confirmed_at timestamptz, rates_current boolean, is_pinned boolean)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  loc_level   text;
  loc_country integer;
begin
  if p_therapy_id is null or p_location_id is null then
    raise exception 'therapy and location are required' using errcode = '22023';
  end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_offset is null or p_offset not between 0 and 10000 then
    raise exception 'offset must be between 0 and 10000' using errcode = '22023';
  end if;
  if not exists (select 1 from public.therapies t where t.id = p_therapy_id and t.is_active) then
    raise exception 'unknown therapy' using errcode = '22023';
  end if;
  if p_service_mode is not null and not exists (select 1 from public.service_modes m where m.code = p_service_mode and m.is_active) then
    raise exception 'unknown service mode' using errcode = '22023';
  end if;
  select ll.code into loc_level
    from public.locations l join public.location_levels ll on ll.id = l.level_id
    where l.id = p_location_id and l.is_active;
  if loc_level is null then
    raise exception 'unknown location' using errcode = '22023';
  end if;
  -- the country of the chosen place (itself, or the nearest ancestor that is a country)
  with recursive up as (
    select l.id, l.parent_id, l.level_id from public.locations l where l.id = p_location_id
    union all
    select l.id, l.parent_id, l.level_id from public.locations l join up on l.id = up.parent_id)
  select max(up.id) into loc_country from up join public.location_levels ll on ll.id = up.level_id where ll.code = 'country';

  return query
  with base as (
    select c.* from public.public_profile_cards c
    where c.therapy_ids @> array[p_therapy_id]
      and (p_service_mode is null or p_service_mode = any (c.service_modes))
  ), grouped as (
    select b.*,
      case
        when p_location_id in (b.city_id, b.region_id, b.country_id) then 1  -- a country search ends here for every profile of that country
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.service_modes)
             and b.country_id = loc_country then 2
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.service_modes) then 3
      end as g
    from base b
  )
  select g.g::smallint, count(*) over (),
         g.profile_id, g.display_name, g.photo_path, g.headline, g.zone, g.approved_at,
         g.city_id, g.city_name, g.region_id, g.region_name, g.country_id, g.country_name, g.country_iso,
         g.therapy_ids, g.therapy_names, g.service_modes, g.session_formats, g.languages, g.rates_from,
         g.rates_confirmed_at, g.rates_current, g.is_pinned
  from grouped g
  where g.g is not null
  -- Order inside a group (owner decision 12/11/2026): the site-owner pin, then current prices, then a photo, then the
  -- oldest approval. Orden dentro del grupo (decisión del titular, 12/11/2026): el perfil fijado del sitio, luego precios
  -- al día, luego foto, luego la aprobación más antigua.
  order by g.g, g.is_pinned desc, g.rates_current desc, (g.photo_path is not null) desc, g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;
revoke execute on function public.search_profiles(integer, integer, text, integer, integer) from public, authenticated, service_role;
-- anon only: public pages are rendered with the anon role (commit 19); as authenticated the view shows just the caller's own
-- profile, so a search would return partial results. / Solo anon: las páginas públicas usan el rol anon (commit 19); como
-- authenticated la vista muestra solo el perfil propio y la búsqueda daría resultados parciales.
grant execute on function public.search_profiles(integer, integer, text, integer, integer) to anon;
