-- Re-acceptance gate: a therapist who has not accepted the CURRENT version of a required document cannot change anything.
-- SECURITY CHANGE: 1 column, 2 callable functions, 2 internal functions, 2 triggers, 4 functions replaced (one added line each).
-- Puerta de re-aceptación: un terapeuta que no aceptó la versión VIGENTE de un documento obligatorio no puede cambiar nada.
-- CAMBIO DE SEGURIDAD: 1 columna, 2 funciones invocables, 2 internas, 2 triggers, 4 funciones reemplazadas (una línea agregada cada una).
--
-- Rules applied (owner decisions of 18/11/2026) / Reglas aplicadas (decisiones del titular del 18/11/2026):
--  * Only SUBSTANTIAL changes ask for a new acceptance: legal_document_types.minimum_version is the oldest version that still
--    counts. A NULL minimum means "not enforced" (the gate is OFF for that document). Raising it is a deliberate data change.
--    Solo los cambios SUSTANCIALES piden aceptar de nuevo: minimum_version es la versión más antigua que todavía vale. NULL =
--    "no se exige" (la puerta está APAGADA para ese documento). Subirla es un cambio de datos deliberado.
--  * A therapist with a pending document cannot change ANYTHING: save a draft, send to review, change or confirm rates,
--    give the photo consent. The block is in the database, not only on the screen.
--    Con un documento pendiente no se cambia NADA: guardar borrador, enviar a revisión, tarifas, consentimiento de la foto.
--    El bloqueo está en la base, no solo en la pantalla.
--  * NEVER blocked (rights of the data subject, Ley 25.326 / GDPR): withdrawing the photo consent, withdrawing the offers
--    consent, discarding an own revision, signing out, reading their own data. Administrators are never blocked.
--    NUNCA se bloquea (derechos del titular): retirar el consentimiento de la foto o de ofertas, descartar una revisión
--    propia, salir, leer los propios datos. Los administradores nunca quedan bloqueados.
--  * The profile that is already published stays published: nothing here touches therapist_profiles.
--    El perfil ya publicado sigue publicado: nada de esto toca therapist_profiles.
--  * Order of rollout: (1) this migration (gate OFF, every minimum is NULL), (2) the app with the banner, (3) turn it ON with
--    the UPDATE in the verification file. Turning it on before the banner would lock people out with no way to accept.
--    Orden de salida: (1) esta migración (puerta APAGADA), (2) la app con el aviso, (3) encenderla con el UPDATE del archivo
--    de verificación. Encenderla antes del aviso dejaría a la gente bloqueada sin forma de aceptar.
--  * Error code AC001 = "acceptance required" (the app shows the banner). / AC001 = "falta aceptar" (la app muestra el aviso).
--  * Identity comes only from auth.uid() (current_person_id()), never from a parameter.
--    La identidad sale solo de auth.uid() (current_person_id()), nunca de un parámetro.

-- ============================================================================
-- 1. Column: the oldest version that still counts / Columna: la versión más antigua que todavía vale
-- ============================================================================
alter table public.legal_document_types
  add column minimum_version text
  check (minimum_version is null or (is_required and minimum_version ~ '^[A-Za-z0-9._-]{1,40}$'));
comment on column public.legal_document_types.minimum_version is
  'Oldest accepted version that still counts for a REQUIRED document; null = not enforced / Versión aceptada más antigua que todavía vale para un documento OBLIGATORIO; nulo = no se exige.';

-- ============================================================================
-- 2. Which required documents does the logged-in person still have to accept? (callable: the banner uses it)
--    ¿Qué documentos obligatorios le falta aceptar a la persona con sesión? (invocable: la usa el aviso)
-- ============================================================================
create function public.my_pending_documents()
returns text[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  person uuid := public.current_person_id();
  result text[];
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  select coalesce(array_agg(d.code order by d.sort_order, d.id), '{}')
    into result
    from public.legal_document_types d
   where d.is_active
     and d.is_required
     and d.minimum_version is not null                       -- not enforced while null / no se exige mientras sea nulo
     and not exists (
       select 1 from public.terms_acceptances a
        where a.person_id = person
          and a.document_type_id = d.id
          and a.revoked_at is null
          and a.version collate "C" >= d.minimum_version collate "C");
  return result;
end
$$;
revoke execute on function public.my_pending_documents() from public, anon, service_role;
grant execute on function public.my_pending_documents() to authenticated;

-- ============================================================================
-- 3. Internal: raise AC001 when something is pending (nobody calls it through the API)
--    Interna: lanza AC001 si hay algo pendiente (nadie la llama por la API)
-- ============================================================================
create function public.assert_current_acceptances()
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if array_length(public.my_pending_documents(), 1) is not null then
    raise exception 'the current legal documents must be accepted first' using errcode = 'AC001';
  end if;
end
$$;
revoke execute on function public.assert_current_acceptances() from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. Accept the pending documents (one call, all of them) / Aceptar los documentos pendientes (una llamada, todos)
--    The keys must be EXACTLY the pending documents, and each version must be at least the minimum.
--    Las claves deben ser EXACTAMENTE los documentos pendientes, y cada versión al menos el mínimo.
-- ============================================================================
create function public.accept_current_documents(p_acceptances jsonb)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person  uuid := public.current_person_id();
  pending text[];
  doc     record;
  v       text;
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_acceptances is null or jsonb_typeof(p_acceptances) <> 'object' then
    raise exception 'acceptances must be an object' using errcode = '22023';
  end if;
  perform 1 from public.people where id = person for update;  -- serialize the same person's calls / serializa las llamadas de la misma persona
  pending := public.my_pending_documents();
  if array_length(pending, 1) is null then
    raise exception 'there is nothing to accept' using errcode = '22023';
  end if;
  if (select array_agg(k order by k) from jsonb_object_keys(p_acceptances) k)
       is distinct from (select array_agg(c order by c) from unnest(pending) c) then
    raise exception 'the acceptances must be exactly the pending documents' using errcode = '22023';
  end if;
  for doc in
    select d.id, d.code, d.minimum_version from public.legal_document_types d where d.code = any (pending)
  loop
    if jsonb_typeof(p_acceptances -> doc.code) is distinct from 'string' then
      raise exception 'the version of % must be text', doc.code using errcode = '22023';
    end if;
    v := p_acceptances ->> doc.code;
    if v !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'invalid version for %', doc.code using errcode = '22023';
    end if;
    if v collate "C" < doc.minimum_version collate "C" then
      raise exception 'the version of % is older than the required one', doc.code using errcode = '22023';
    end if;
    -- a new row; the old acceptance stays as history / fila nueva; la aceptación anterior queda como historia
    insert into public.terms_acceptances (person_id, document_type_id, version) values (person, doc.id, v);
  end loop;
end
$$;
revoke execute on function public.accept_current_documents(jsonb) from public, anon, service_role;
grant execute on function public.accept_current_documents(jsonb) to authenticated;

-- ============================================================================
-- 5. Direct writes of the therapist: profile_revisions and location_requests (RLS lets them, this blocks them)
--    Escrituras directas del terapeuta: profile_revisions y location_requests (la RLS las permite, esto las bloquea)
--    Only API roles are checked (same pattern as therapist_profiles_guard); SECURITY DEFINER functions are gated inside.
--    Solo se controlan los roles de la API (mismo patrón que therapist_profiles_guard); las funciones SECURITY DEFINER
--    llevan la puerta adentro. Administrators are exempt. / Los administradores quedan exentos.
-- ============================================================================
create function public.require_current_acceptances()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if current_user in ('anon', 'authenticated')
     and public.current_person_id() is not null
     and not public.is_admin()
     and array_length(public.my_pending_documents(), 1) is not null then
    raise exception 'the current legal documents must be accepted first' using errcode = 'AC001';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;
revoke execute on function public.require_current_acceptances() from public, anon, authenticated, service_role;

-- The trigger names start with "acceptance_gate_" on purpose: triggers of the same moment run in alphabetical order, so the
-- gate runs BEFORE the other validations and the therapist sees "accept the documents" instead of an unrelated validation error.
-- Los nombres empiezan con "acceptance_gate_" a propósito: los triggers del mismo momento corren en orden alfabético, así que la
-- puerta corre ANTES que las otras validaciones y la persona ve "aceptá los documentos" y no un error de validación ajeno.
create trigger acceptance_gate_profile_revisions
  before insert or update or delete on public.profile_revisions
  for each row execute function public.require_current_acceptances();
create trigger acceptance_gate_location_requests
  before insert or update or delete on public.location_requests
  for each row execute function public.require_current_acceptances();

-- ============================================================================
-- 6. Functions replaced: same signatures and permissions, ONE line added after the login check.
--    Funciones reemplazadas: mismas firmas y permisos, UNA línea agregada tras el chequeo de sesión.
--    Copied from 20261117050000 (submit_revision), 20261112170000 (update_my_rates, confirm_my_rates) and
--    20261116030000 (set_photo_consent). / Copiadas de esas migraciones.
-- ============================================================================
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
  -- legal gate: the current documents must be accepted first / puerta legal: antes hay que aceptar los documentos vigentes
  perform public.assert_current_acceptances();

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

create or replace function public.update_my_rates(p_rates jsonb)
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
  -- legal gate: the current documents must be accepted first / puerta legal: antes hay que aceptar los documentos vigentes
  perform public.assert_current_acceptances();
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

create or replace function public.confirm_my_rates()
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
  -- legal gate: the current documents must be accepted first / puerta legal: antes hay que aceptar los documentos vigentes
  perform public.assert_current_acceptances();
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

create or replace function public.set_photo_consent(p_value boolean, p_version text default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person  uuid := public.current_person_id();
  type_id smallint;
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'a value is required' using errcode = '22023';
  end if;
  -- giving the consent is gated; WITHDRAWING it never is / dar el consentimiento tiene puerta; RETIRARLO nunca
  if p_value then
    perform public.assert_current_acceptances();
  end if;
  select id into strict type_id from public.legal_document_types where code = 'photo_consent' and is_active;
  perform 1 from public.people where id = person for update;  -- serialize the same person's calls

  if p_value then
    if p_version is null or p_version !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'a valid document version is required' using errcode = '22023';
    end if;
    if not exists (select 1 from public.terms_acceptances
                   where person_id = person and document_type_id = type_id and version = p_version and revoked_at is null) then
      -- a consent given for an older text stays as history; the new text gets its own row
      -- un consentimiento dado para un texto anterior queda como historia; el texto nuevo tiene su propia fila
      insert into public.terms_acceptances (person_id, document_type_id, version) values (person, type_id, p_version);
    end if;
  else
    update public.terms_acceptances set revoked_at = now()
      where person_id = person and document_type_id = type_id and revoked_at is null;
  end if;
end
$$;
