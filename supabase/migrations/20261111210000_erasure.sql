-- Erasure of a therapist (right to be forgotten). SECURITY CHANGE: 1 table, 4 server-only functions, 1 helper, 1 setting.
-- Eliminación de un terapeuta (derecho al olvido). CAMBIO DE SEGURIDAD: 1 tabla, 4 funciones solo de servidor, 1 ayuda, 1 ajuste.
--
--  * Erasing deletes the profile and everything that hangs from it (contacts, therapies, rates, revisions, reveal
--    counters; cascade) and anonymizes the person row (name replaced, email and login link cleared, roles removed). The
--    shape of an erased person is already enforced by the constraint people_erased_shape (commit 8).
--    Eliminar borra el perfil y todo lo que cuelga de él (contactos, terapias, tarifas, revisiones, contadores de revelado;
--    en cascada) y anonimiza la ficha de la persona (nombre reemplazado, mail y vínculo de acceso vacíos, roles quitados).
--  * Reports about the profile keep existing without profile, but their free-text details (that can name the therapist) are
--    erased. The reporter's optional email stays until the retention of closed reports (another person's data).
--    Las denuncias sobre el perfil siguen existiendo sin perfil, pero se borra su texto libre (puede nombrar al terapeuta).
--    El mail opcional del denunciante queda hasta la retención de denuncias cerradas (es dato de otra persona).
--  * What stays, and why: a keyed fingerprint (HMAC-SHA256, computed by the website server with a secret key that never
--    reaches the database) of each email and phone, for 12 months (decided by the owner), with a counter. It lets the
--    server notice a person who erases and comes back to avoid a moderation decision. It cannot be reversed and links to no
--    person row. An anonymized person row (no personal data), the acceptance history (evidence, no personal data once the
--    person is anonymized) and the moderation records (who decided, when, why; no link to the profile) also stay.
--    Qué queda y por qué: una huella con clave (HMAC-SHA256, calculada por el servidor de la web con una clave secreta que
--    nunca llega a la base) de cada mail y teléfono, durante 12 meses (decidido por el dueño), con un contador. Permite
--    notar a quien elimina y vuelve para evitar una decisión de moderación. No se puede revertir y no apunta a ninguna
--    ficha. También quedan la ficha anonimizada, el historial de aceptaciones y los registros de moderación.
--  * Only the website server (service_role) can run these functions; the server checks WHO asks (the therapist for their own
--    profile, or an administrator) before calling. The database never sees the HMAC key.
--    Solo el servidor de la web (service_role) corre estas funciones; el servidor verifica QUIÉN pide (el terapeuta sobre su
--    perfil, o un administrador) antes de llamar. La base nunca ve la clave HMAC.
--  * Server steps after erase_therapist returns (fixed order, database first): delete the login user in Auth, delete the
--    photo files of the old profile. If one fails the data is already gone from the database; a later cleanup job removes
--    orphans (Auth users without a person, photo folders without a profile). / Pasos del servidor luego de erase_therapist
--    (orden fijo, primero la base): borrar el usuario en Auth y las fotos del perfil viejo. Si uno falla, los datos ya no
--    están en la base; una tarea posterior limpia los huérfanos.

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
    when 'retention_unmet_searches_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_contact_reveals_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_reports_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_erasure_fingerprints_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('retention_erasure_fingerprints_months', '12', false,
   'Months to keep the fingerprints of erased therapists (1-120) / Meses que se conservan las huellas de terapeutas eliminados (1-120)');

-- ============================================================================
-- 2. erasure_fingerprints (no API role has any access)
-- ============================================================================
create table public.erasure_fingerprints (
  id              bigint generated always as identity primary key,
  contact_type_id smallint    not null references public.contact_types (id) on delete restrict,
  fingerprint     text        not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  erasure_count   integer     not null default 1 check (erasure_count between 1 and 1000),
  first_erased_at timestamptz not null default now(),
  last_erased_at  timestamptz not null default now(),
  expires_at      timestamptz not null,
  unique (contact_type_id, fingerprint),
  check (expires_at > last_erased_at)
);
create index erasure_fingerprints_expires_idx on public.erasure_fingerprints (expires_at);
comment on table public.erasure_fingerprints is
  'Keyed hashes (HMAC) of the email and phone of erased therapists, 12 months, with a counter. Links to no person / Huellas con clave de mail y teléfono de terapeutas eliminados, 12 meses, con contador. No apunta a ninguna ficha.';

-- SECURITY: RLS on, no GRANT and no policy for any API role: nobody reads it, not even the admin (hashes mean nothing to a person).
-- SEGURIDAD: RLS activa, sin GRANT ni política para ningún rol de la API: nadie la lee, ni el admin (los hashes no dicen nada).
alter table public.erasure_fingerprints enable row level security;

-- ============================================================================
-- 3. parse_fingerprints (internal helper) / ayuda interna
-- ============================================================================
-- Input: [{"type": "email" | "phone", "hash": "<64 lower-case hex>"}, ...] (at most 20).
create function public.parse_fingerprints(p_fingerprints jsonb, p_require_nonempty boolean)
returns table (contact_type_id smallint, fingerprint text)
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  item jsonb;
  t    smallint;
  h    text;
begin
  if p_fingerprints is null or jsonb_typeof(p_fingerprints) <> 'array' then
    raise exception 'fingerprints must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_fingerprints) > 20 then
    raise exception 'at most 20 fingerprints' using errcode = '22023';
  end if;
  if p_require_nonempty and jsonb_array_length(p_fingerprints) = 0 then
    raise exception 'at least one fingerprint is required' using errcode = '22023';
  end if;
  for item in select e from jsonb_array_elements(p_fingerprints) e loop
    if jsonb_typeof(item) <> 'object' or (item - 'type' - 'hash') <> '{}'::jsonb
       or jsonb_typeof(item -> 'type') is distinct from 'string' or jsonb_typeof(item -> 'hash') is distinct from 'string' then
      raise exception 'each fingerprint is {"type": ..., "hash": ...}' using errcode = '22023';
    end if;
    h := item ->> 'hash';
    if h !~ '^[0-9a-f]{64}$' then
      raise exception 'a hash must be 64 lower-case hexadecimal characters' using errcode = '22023';
    end if;
    select ct.id into t from public.contact_types ct where ct.code = item ->> 'type' and ct.is_private and ct.is_active;
    if t is null then
      raise exception 'unknown fingerprint type' using errcode = '22023';
    end if;
    contact_type_id := t;
    fingerprint := h;
    return next;
  end loop;
end
$$;
revoke execute on function public.parse_fingerprints(jsonb, boolean) from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. erasure_material: the values the server turns into fingerprints
-- ============================================================================
-- Emails in lower case and phones as digits only. Nothing for an erased or unknown person.
-- Mails en minúscula y teléfonos solo con dígitos. Nada para una persona eliminada o inexistente.
create function public.erasure_material(p_person_id uuid)
returns table (contact_type text, value text)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select 'email'::text, p.email from public.people p where p.id = p_person_id and p.erased_at is null and p.email is not null
  union
  select ct.code::text,
         case when ct.code = 'phone' then regexp_replace(pc.value, '[^0-9]', '', 'g') else lower(pc.value) end
    from public.people p
    join public.therapist_profiles tp on tp.person_id = p.id
    join public.profile_contacts pc on pc.profile_id = tp.id
    join public.contact_types ct on ct.id = pc.contact_type_id
   where p.id = p_person_id and p.erased_at is null and ct.code in ('email', 'phone')
$$;
revoke execute on function public.erasure_material(uuid) from public, anon, authenticated;
grant execute on function public.erasure_material(uuid) to service_role;

-- ============================================================================
-- 5. erase_therapist (one transaction)
-- ============================================================================
create function public.erase_therapist(p_person_id uuid, p_fingerprints jsonb, p_requested_by text)
returns table (auth_user_id uuid, profile_id uuid, photo_path text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  person  public.people;
  prof    public.therapist_profiles;
  months  integer;
  erased_status smallint := (select id from public.profile_statuses where code = 'erased');
begin
  if p_requested_by is null or p_requested_by not in ('self', 'admin') then
    raise exception 'requested_by must be self or admin' using errcode = '22023';
  end if;
  -- validate before touching anything / validar antes de tocar nada
  perform 1 from public.parse_fingerprints(p_fingerprints, true);
  select (value::text)::int into months from public.app_settings where key = 'retention_erasure_fingerprints_months';
  if months is null then
    raise exception 'setting retention_erasure_fingerprints_months is missing' using errcode = '23514';
  end if;

  select * into person from public.people where id = p_person_id for update;
  if not found then
    raise exception 'person not found' using errcode = 'P0002';
  end if;
  if person.erased_at is not null then
    raise exception 'the person is already erased' using errcode = '55000';
  end if;
  if exists (select 1 from public.person_roles pr join public.roles r on r.id = pr.role_id where pr.person_id = person.id and r.code = 'admin') then
    raise exception 'an administrator cannot be erased here' using errcode = '55000';
  end if;
  select * into prof from public.therapist_profiles where person_id = person.id for update;

  if prof.id is not null then
    update public.reports set details = null where reports.profile_id = prof.id;
  end if;

  -- fingerprints: a repeated erasure adds to the counter and renews the expiry; an expired row not yet purged restarts
  insert into public.erasure_fingerprints as f (contact_type_id, fingerprint, expires_at)
    select distinct s.contact_type_id, s.fingerprint, now() + make_interval(months => months)
      from public.parse_fingerprints(p_fingerprints, true) s
    on conflict (contact_type_id, fingerprint) do update
      set erasure_count   = case when f.expires_at < now() then 1 else least(f.erasure_count + 1, 1000) end,
          first_erased_at = case when f.expires_at < now() then now() else f.first_erased_at end,
          last_erased_at  = now(),
          expires_at      = excluded.expires_at;

  -- the record of the decision, with no link to the profile / el registro de la decisión, sin vínculo al perfil
  insert into public.moderation_events (profile_id, actor_person_id, profile_status_id, reason)
    values (null, person.id, erased_status,
            case p_requested_by when 'self' then 'erasure requested by the therapist' else 'erasure requested by an administrator' end);

  if prof.id is not null then
    delete from public.therapist_profiles where id = prof.id;   -- children go by cascade
  end if;
  delete from public.person_roles where person_id = person.id;
  update public.people
     set full_name = 'Persona eliminada', email = null, auth_user_id = null, erased_at = now()
   where id = person.id;

  auth_user_id := person.auth_user_id;
  profile_id   := prof.id;
  photo_path   := prof.photo_path;
  return next;
end
$$;
revoke execute on function public.erase_therapist(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.erase_therapist(uuid, jsonb, text) to service_role;

-- ============================================================================
-- 6. check_erasure_fingerprints: how many times these values were erased (live fingerprints only)
-- ============================================================================
create function public.check_erasure_fingerprints(p_fingerprints jsonb)
returns integer
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  total integer;
begin
  -- validate first: a join against an empty table would never run the parser / validar primero: un join contra una tabla vacía no ejecutaría el parser
  perform 1 from public.parse_fingerprints(p_fingerprints, false);
  select coalesce(sum(f.erasure_count), 0)::int into total
    from public.erasure_fingerprints f
    join (select distinct s.contact_type_id, s.fingerprint from public.parse_fingerprints(p_fingerprints, false) s) q
      on q.contact_type_id = f.contact_type_id and q.fingerprint = f.fingerprint
   where f.expires_at > now();
  return total;
end
$$;
revoke execute on function public.check_erasure_fingerprints(jsonb) from public, anon, authenticated;
grant execute on function public.check_erasure_fingerprints(jsonb) to service_role;

-- ============================================================================
-- 7. Retention / Retención
-- ============================================================================
create function public.purge_expired_erasure_fingerprints()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  removed integer;
begin
  delete from public.erasure_fingerprints where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.purge_expired_erasure_fingerprints() from public, anon, authenticated;
grant execute on function public.purge_expired_erasure_fingerprints() to service_role;
