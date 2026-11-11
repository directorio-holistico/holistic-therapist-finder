-- Submitting and discarding revisions (therapist side). SECURITY CHANGE: 2 callable functions, 3 internal ones, 3 settings.
-- Enviar y descartar revisiones (lado del terapeuta). CAMBIO DE SEGURIDAD: 2 funciones invocables, 3 internas, 3 ajustes.
--
-- Rules applied / Reglas aplicadas:
--  * Decision 5 (11/11/2026): review deadlines count BUSINESS days (Mon-Fri, Argentina time, no holidays in
--    Phase 1): 7 for a first submission, 3 for a change, 1 for high priority. All configurable in app_settings.
--    Decisión 5: los plazos cuentan DÍAS HÁBILES (lun-vie, hora de Argentina, sin feriados en la Fase 1): 7
--    para un alta, 3 para un cambio, 1 para prioridad alta. Todos configurables en app_settings.
--  * Restricted terms FLAG, never block: submitting always works; the flagged terms are stored and returned.
--    Los términos restringidos MARCAN, nunca bloquean: enviar siempre funciona; se guardan y se devuelven.
--  * Identity comes only from auth.uid() (through current_person_id()), never from a parameter.
--    La identidad sale solo de auth.uid() (por current_person_id()), nunca de un parámetro.
--  * A therapist cannot touch a revision that is not theirs, and the function does not reveal if it exists.
--    Un terapeuta no toca una revisión ajena, y la función no revela si existe.

-- ============================================================================
-- 1. Settings: review deadlines (business days) / Ajustes: plazos de revisión (días hábiles)
-- ============================================================================
alter table public.app_settings drop constraint app_settings_value_valid;
alter table public.app_settings add constraint app_settings_value_valid check (
  case key
    when 'max_therapies_per_profile'
      then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
    when 'review_days_initial' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_update' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_priority' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    else true
  end);

insert into public.app_settings (key, value, is_public, description) values
  ('review_days_initial',  '7', true, 'Business days to review a first submission (1-30) / Días hábiles para revisar un alta (1-30)'),
  ('review_days_update',   '3', true, 'Business days to review a change (1-30) / Días hábiles para revisar un cambio (1-30)'),
  ('review_days_priority', '1', true, 'Business days to review a high priority revision (1-30) / Días hábiles para una revisión de prioridad alta (1-30)');

-- ============================================================================
-- 2. Internal helpers (nobody calls them through the API) / Auxiliares internas (nadie las llama por la API)
-- ============================================================================

-- add_business_days: Monday to Friday in Argentina time, no holidays (Phase 1); keeps the time of day.
-- add_business_days: lunes a viernes en hora de Argentina, sin feriados (Fase 1); conserva la hora.
create function public.add_business_days(p_from timestamptz, p_days integer)
returns timestamptz
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  tz constant text := 'America/Argentina/Buenos_Aires';
  local_ts timestamp := p_from at time zone tz;
  counted integer := 0;
begin
  if p_days is null or p_days < 0 or p_days > 60 then
    raise exception 'p_days must be between 0 and 60' using errcode = '22023';
  end if;
  while counted < p_days loop
    local_ts := local_ts + interval '1 day';
    if extract(isodow from local_ts) < 6 then
      counted := counted + 1;
    end if;
  end loop;
  return local_ts at time zone tz;
end
$$;
revoke execute on function public.add_business_days(timestamptz, integer) from public, anon, authenticated, service_role;

-- match_restricted_terms: the matching logic, without the login check and the length limit.
-- match_restricted_terms: la lógica de coincidencia, sin el chequeo de sesión ni el límite de largo.
create function public.match_restricted_terms(p_text text)
returns text[]
language sql
stable
set search_path = pg_catalog, public
as $$
  select coalesce((
    select array_agg(t.term order by t.term)
    from public.restricted_terms t
    where t.is_active
      and public.normalize_text(coalesce(p_text, '')) ~
          ('(^|[^a-z0-9])' || regexp_replace(t.term, '([^a-z0-9 ])', '\\\1', 'g') || '([^a-z0-9]|$)')
  ), '{}')
$$;
revoke execute on function public.match_restricted_terms(text) from public, anon, authenticated, service_role;

-- find_restricted_terms now delegates to it (same behavior as before) / ahora delega en esa (mismo comportamiento)
create or replace function public.find_restricted_terms(p_text text)
returns text[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_text is null then
    return '{}';
  end if;
  if char_length(p_text) > 5000 then
    raise exception 'text too long (max 5000 characters)' using errcode = '22023';
  end if;
  return public.match_restricted_terms(p_text);
end
$$;

-- ============================================================================
-- 3. submit_revision / discard_revision
-- ============================================================================

-- submit_revision: draft -> pending_review. Stores the flagged terms and the due date, returns the flagged terms.
-- submit_revision: borrador -> pendiente de revisión. Guarda los términos marcados y la fecha límite, y los devuelve.
create function public.submit_revision(p_revision_id uuid)
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
  allowed_keys  constant text[] := array['headline', 'zone', 'practice_start_year', 'location_id', 'photo_path',
                                          'therapies', 'languages', 'service_modes', 'session_formats', 'contacts'];
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
revoke execute on function public.submit_revision(uuid) from public, anon, service_role;
grant execute on function public.submit_revision(uuid) to authenticated;

-- discard_revision: the therapist withdraws their own draft or pending revision.
-- discard_revision: el terapeuta retira su propia revisión en borrador o pendiente.
create function public.discard_revision(p_revision_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person    uuid := public.current_person_id();
  rev       public.profile_revisions%rowtype;
  open_codes constant text[] := array['draft', 'pending_review'];
  current_code text;
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
  select code into strict current_code from public.revision_statuses where id = rev.status_id;
  if current_code <> all (open_codes) then
    raise exception 'only an open revision can be discarded' using errcode = '55000';
  end if;
  update public.profile_revisions
     set status_id = (select id from public.revision_statuses where code = 'discarded'),
         closed_at = now(),
         decided_at = now()
   where id = rev.id;
end
$$;
revoke execute on function public.discard_revision(uuid) from public, anon, service_role;
grant execute on function public.discard_revision(uuid) to authenticated;
