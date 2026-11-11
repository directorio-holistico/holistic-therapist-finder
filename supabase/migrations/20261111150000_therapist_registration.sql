-- Therapist registration and legal acceptances. SECURITY CHANGE: 1 table, 2 callable functions, 1 trigger.
-- Alta del terapeuta y aceptaciones legales. CAMBIO DE SEGURIDAD: 1 tabla, 2 funciones invocables, 1 trigger.
--
-- Model change (to be confirmed) / Cambio al modelo (a confirmar): a 35th table, the catalog legal_document_types,
-- because the rules forbid fixed CHECK lists for catalogs. It says which documents exist and which are required.
-- una tabla 35, el catálogo legal_document_types, porque las reglas prohíben listas fijas en CHECK para catálogos.
--
-- Rules applied / Reglas aplicadas:
--  * The user is created by the authentication service (by email link). Then, once the email is VERIFIED, the user calls
--    register_therapist: it creates the person, the therapist role, an empty unpublished profile and the acceptances,
--    all in one transaction. Name and email come from the call and from auth.users, never an identity from a parameter.
--    El usuario lo crea el servicio de autenticación (por enlace al mail). Con el mail VERIFICADO, llama a
--    register_therapist: crea persona, rol, perfil vacío sin publicar y aceptaciones, en una sola transacción.
--  * Required documents (terms, privacy, legal declaration) must all be accepted. The offers consent (decision 36) is
--    optional: absent = not given (unchecked by default). It can be revoked and given again; each acceptance is evidence
--    and is never edited, only revoked.
--    Los documentos obligatorios deben aceptarse todos. El consentimiento de ofertas (decisión 36) es opcional: ausente =
--    no dado (desmarcado por defecto). Se puede retirar y volver a dar; cada aceptación es evidencia y no se edita.
--  * Nobody writes terms_acceptances through the API: only these functions.
--    Nadie escribe terms_acceptances por la API: solo estas funciones.

-- ============================================================================
-- 1. Catalog of legal documents / Catálogo de documentos legales
-- ============================================================================
create table public.legal_document_types (
  id          smallint generated always as identity primary key,
  code        text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  is_required boolean  not null,
  sort_order  smallint not null default 0,
  is_active   boolean  not null default true
);
comment on table public.legal_document_types is
  'Legal documents a therapist accepts; is_required = needed to register / Documentos legales que acepta el terapeuta; is_required = necesario para registrarse.';
insert into public.legal_document_types (code, is_required, sort_order) values
  ('terms', true, 1), ('privacy', true, 2), ('legal_declaration', true, 3), ('offers_consent', false, 4);

alter table public.legal_document_types enable row level security;
grant select on public.legal_document_types to authenticated;
create policy legal_document_types_select on public.legal_document_types
  for select to authenticated using (true);

-- ============================================================================
-- 2. Acceptances (evidence) / Aceptaciones (evidencia)
-- ============================================================================
create table public.terms_acceptances (
  id               uuid primary key default gen_random_uuid(),
  person_id        uuid     not null references public.people (id) on delete cascade,
  document_type_id smallint not null references public.legal_document_types (id) on delete restrict,
  version          text     not null check (version ~ '^[A-Za-z0-9._-]{1,40}$'),
  accepted_at      timestamptz not null default now(),
  revoked_at       timestamptz,
  check (revoked_at is null or revoked_at >= accepted_at)
);
create unique index terms_acceptances_one_active
  on public.terms_acceptances (person_id, document_type_id, version) where revoked_at is null;
create index terms_acceptances_person_idx on public.terms_acceptances (person_id);
comment on table public.terms_acceptances is
  'Evidence of what each person accepted and when; only revoked_at can change, and only for optional documents / Evidencia de lo que aceptó cada persona; solo cambia revoked_at, y solo en documentos opcionales.';

create function public.terms_acceptances_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  required_doc boolean;
begin
  if tg_op = 'INSERT' then
    if new.revoked_at is not null then
      raise exception 'an acceptance cannot be created already revoked' using errcode = '23514';
    end if;
    return new;
  end if;
  -- UPDATE: the evidence is immutable; only revoked_at may go from null to a date
  if new.id is distinct from old.id or new.person_id is distinct from old.person_id
     or new.document_type_id is distinct from old.document_type_id or new.version is distinct from old.version
     or new.accepted_at is distinct from old.accepted_at then
    raise exception 'acceptance evidence cannot be edited' using errcode = '23514';
  end if;
  if old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'a revoked acceptance cannot be changed' using errcode = '23514';
  end if;
  if old.revoked_at is null and new.revoked_at is not null then
    select is_required into strict required_doc from public.legal_document_types where id = new.document_type_id;
    if required_doc then
      raise exception 'a required document cannot be revoked (leave the service instead)' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
create trigger terms_acceptances_guard
  before insert or update on public.terms_acceptances
  for each row execute function public.terms_acceptances_guard();
revoke execute on function public.terms_acceptances_guard() from public, anon, authenticated, service_role;

-- SECURITY: RLS + GRANT. Read only; nobody writes through the API.
-- SEGURIDAD: RLS + GRANT. Solo lectura; nadie escribe por la API.
alter table public.terms_acceptances enable row level security;
grant select on public.terms_acceptances to authenticated;
create policy terms_acceptances_select_own on public.terms_acceptances
  for select to authenticated
  using (person_id = (select public.current_person_id()));
create policy terms_acceptances_select_admin on public.terms_acceptances
  for select to authenticated
  using ((select public.is_admin()));

-- ============================================================================
-- 3. register_therapist
-- ============================================================================
-- p_acceptances is an object {document code: version}, e.g. {"terms":"2026-11","privacy":"2026-11",
-- "legal_declaration":"2026-11","offers_consent":"2026-11"}. Returns the id of the new (empty, unpublished) profile.
-- p_acceptances es un objeto {código de documento: versión}. Devuelve el id del perfil nuevo (vacío, sin publicar).
create function public.register_therapist(p_full_name text, p_acceptances jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  uid          uuid := auth.uid();
  auth_email   text;
  confirmed_at timestamptz;
  name         text := btrim(p_full_name);
  new_person   uuid;
  new_profile  uuid;
  doc          record;
  given        text;
  known_codes  text[];
begin
  if uid is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  select lower(btrim(u.email)), u.email_confirmed_at into auth_email, confirmed_at from auth.users u where u.id = uid;
  if not found or auth_email is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if confirmed_at is null then
    raise exception 'verify your email first' using errcode = '42501';
  end if;
  if exists (select 1 from public.people where auth_user_id = uid) then
    raise exception 'already registered' using errcode = '23505';
  end if;

  if name is null or char_length(name) not between 1 and 120 then
    raise exception 'the name must have 1 to 120 characters' using errcode = '22023';
  end if;
  if p_acceptances is null or jsonb_typeof(p_acceptances) <> 'object' then
    raise exception 'acceptances must be an object' using errcode = '22023';
  end if;
  select coalesce(array_agg(code), '{}') into known_codes from public.legal_document_types where is_active;
  if exists (select 1 from jsonb_object_keys(p_acceptances) k where k <> all (known_codes)) then
    raise exception 'unknown document in acceptances' using errcode = '22023';
  end if;

  begin
    insert into public.people (auth_user_id, full_name, email) values (uid, name, auth_email) returning id into new_person;
  exception when unique_violation then
    raise exception 'already registered' using errcode = '23505';
  end;
  insert into public.person_roles (person_id, role_id) values (new_person, (select id from public.roles where code = 'therapist'));
  insert into public.therapist_profiles (person_id, status_id)
    values (new_person, (select id from public.profile_statuses where code = 'unpublished'))
    returning id into new_profile;

  for doc in select id, code, is_required from public.legal_document_types where is_active order by sort_order loop
    if jsonb_typeof(p_acceptances -> doc.code) is distinct from 'string' then
      if doc.is_required then
        raise exception 'you must accept the document: %', doc.code using errcode = '22023';
      elsif p_acceptances ? doc.code and jsonb_typeof(p_acceptances -> doc.code) <> 'null' then
        raise exception 'the version of % must be text', doc.code using errcode = '22023';
      end if;
      continue;  -- optional and not given
    end if;
    given := p_acceptances ->> doc.code;
    if given !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'invalid version for %', doc.code using errcode = '22023';
    end if;
    insert into public.terms_acceptances (person_id, document_type_id, version) values (new_person, doc.id, given);
  end loop;

  return new_profile;
end
$$;
revoke execute on function public.register_therapist(text, jsonb) from public, anon, service_role;
grant execute on function public.register_therapist(text, jsonb) to authenticated;

-- ============================================================================
-- 4. set_offers_consent: give (with the version shown) or withdraw the optional consent
-- ============================================================================
create function public.set_offers_consent(p_value boolean, p_version text default null)
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
  select id into strict type_id from public.legal_document_types where code = 'offers_consent' and is_active;
  perform 1 from public.people where id = person for update;  -- serialize the same person's calls

  if p_value then
    if p_version is null or p_version !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'a valid document version is required' using errcode = '22023';
    end if;
    if not exists (select 1 from public.terms_acceptances
                   where person_id = person and document_type_id = type_id and revoked_at is null) then
      insert into public.terms_acceptances (person_id, document_type_id, version) values (person, type_id, p_version);
    end if;
  else
    update public.terms_acceptances set revoked_at = now()
      where person_id = person and document_type_id = type_id and revoked_at is null;
  end if;
end
$$;
revoke execute on function public.set_offers_consent(boolean, text) from public, anon, service_role;
grant execute on function public.set_offers_consent(boolean, text) to authenticated;
