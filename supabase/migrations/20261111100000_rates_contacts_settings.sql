-- Rates, contacts and application settings. SECURITY CHANGE: 3 tables, 4 triggers, 1 policy that allows writes.
-- Tarifas, contactos y ajustes de la aplicación. CAMBIO DE SEGURIDAD: 3 tablas, 4 triggers, 1 política que permite escribir.
--
-- Rules applied / Reglas aplicadas:
--  * profile_therapy_rates and profile_contacts: same access as the other profile tables (own / admin read,
--    nobody writes through the API, anon nothing). Phones and emails are NEVER exposed to anon: the only way
--    out will be the reveal_contact function (later commit).
--    profile_therapy_rates y profile_contacts: mismo acceso que las demás tablas del perfil (lectura propia /
--    admin, nadie escribe por la API, anon nada). Teléfonos y mails NUNCA se exponen a anon: la única salida
--    será la función reveal_contact (commit posterior).
--  * app_settings: authenticated reads PUBLIC keys only; an admin reads all and may change ONLY the `value`
--    column (column-level grant), validated by a CHECK. Keys are added by migrations, never through the API.
--    app_settings: authenticated lee solo claves PÚBLICAS; un admin lee todas y puede cambiar SOLO la columna
--    `value` (permiso por columna), validada por un CHECK. Las claves se agregan por migración, nunca por la API.

-- ============================================================================
-- 1. app_settings
-- ============================================================================
create table public.app_settings (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  value       jsonb not null,
  is_public   boolean not null default false,
  description text not null check (char_length(description) between 1 and 300),
  -- Known keys are validated; evaluated with CASE so the cast never runs on the wrong type.
  -- Las claves conocidas se validan; con CASE para que el cast no corra sobre un tipo equivocado.
  constraint app_settings_value_valid check (
    case key
      when 'max_therapies_per_profile'
        then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
      else true
    end)
);
comment on table public.app_settings is 'Configurable rules and limits / Reglas y límites configurables.';

insert into public.app_settings (key, value, is_public, description) values
  ('max_therapies_per_profile', '4', true, 'Maximum number of therapies per profile (1-10) / Máximo de terapias por perfil (1-10)');

-- ============================================================================
-- 2. Rates / Tarifas
-- ============================================================================
create table public.profile_therapy_rates (
  profile_id       uuid          not null,
  therapy_id       integer       not null,
  rate_audience_id smallint      not null references public.rate_audiences (id) on delete restrict,
  amount           numeric(12,2) not null check (amount >= 0),
  currency_id      smallint      not null references public.currencies (id) on delete restrict,
  primary key (profile_id, therapy_id, rate_audience_id),
  foreign key (profile_id, therapy_id) references public.profile_therapies (profile_id, therapy_id) on delete cascade
);
comment on table public.profile_therapy_rates is
  'Optional rate per therapy and audience (own country / other countries); one currency per audience in a profile / Tarifa opcional por terapia y audiencia; una moneda por audiencia en el perfil.';

create function public.profile_therapy_rates_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  minor smallint;
begin
  select minor_units into strict minor from public.currencies where id = new.currency_id;
  if new.amount <> round(new.amount, minor) then
    raise exception 'amount has more decimals than the currency allows' using errcode = '23514';
  end if;
  -- lock the profile so two concurrent writes cannot mix currencies / bloquear el perfil para que dos escrituras simultáneas no mezclen monedas
  perform 1 from public.therapist_profiles where id = new.profile_id for update;
  if exists (
    select 1 from public.profile_therapy_rates r
    where r.profile_id = new.profile_id
      and r.rate_audience_id = new.rate_audience_id
      and r.therapy_id <> new.therapy_id
      and r.currency_id <> new.currency_id) then
    raise exception 'one currency per audience within a profile' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger profile_therapy_rates_guard
  before insert or update on public.profile_therapy_rates
  for each row execute function public.profile_therapy_rates_guard();
revoke execute on function public.profile_therapy_rates_guard() from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. Maximum therapies per profile (configurable) / Máximo de terapias por perfil (configurable)
-- ============================================================================
create function public.profile_therapies_limit()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  max_allowed integer;
  current_count integer;
begin
  select (value::text)::int into max_allowed from public.app_settings where key = 'max_therapies_per_profile';
  if max_allowed is null then
    raise exception 'setting max_therapies_per_profile is missing' using errcode = '23514';
  end if;
  perform 1 from public.therapist_profiles where id = new.profile_id for update;
  select count(*) into current_count from public.profile_therapies where profile_id = new.profile_id;
  if current_count >= max_allowed then
    raise exception 'a profile can have at most % therapies', max_allowed using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger profile_therapies_limit
  before insert on public.profile_therapies
  for each row execute function public.profile_therapies_limit();
revoke execute on function public.profile_therapies_limit() from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. Contacts / Contactos
-- ============================================================================
create table public.profile_contacts (
  profile_id       uuid     not null references public.therapist_profiles (id) on delete cascade,
  contact_type_id  smallint not null references public.contact_types (id) on delete restrict,
  value            text     not null check (value = btrim(value) and char_length(value) between 1 and 300),
  accepts_whatsapp boolean  not null default false,
  primary key (profile_id, contact_type_id)
);
comment on table public.profile_contacts is
  'Phone (required), email and website; stored as text / Teléfono (obligatorio), mail y web; guardados como texto.';

create function public.profile_contacts_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  type_code text;
  profile_status text;
begin
  if tg_op = 'DELETE' then
    select ct.code into type_code from public.contact_types ct where ct.id = old.contact_type_id;
    select ps.code into profile_status
      from public.therapist_profiles tp join public.profile_statuses ps on ps.id = tp.status_id
      where tp.id = old.profile_id;
    -- profile_status is null while the profile itself is being deleted (cascade): that is allowed
    -- profile_status es nulo mientras se borra el perfil entero (cascada): eso se permite
    if type_code = 'phone' and profile_status = 'published' then
      raise exception 'a published profile cannot lose its phone' using errcode = '23514';
    end if;
    return old;
  end if;

  select code into strict type_code from public.contact_types where id = new.contact_type_id;
  if new.accepts_whatsapp and type_code <> 'phone' then
    raise exception 'accepts_whatsapp only applies to the phone' using errcode = '23514';
  end if;
  if type_code = 'phone' then
    if new.value !~ '^\+?[0-9 ()-]+$' or length(regexp_replace(new.value, '[^0-9]', '', 'g')) not between 6 and 15 then
      raise exception 'invalid phone' using errcode = '23514';
    end if;
  elsif type_code = 'email' then
    if new.value <> lower(new.value) or new.value !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' then
      raise exception 'invalid email (lower case, name@domain.tld)' using errcode = '23514';
    end if;
  elsif type_code = 'website' then
    if new.value !~ '^https?://[^ ]+$' then
      raise exception 'invalid website (must start with http:// or https://)' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
create trigger profile_contacts_guard
  before insert or update or delete on public.profile_contacts
  for each row execute function public.profile_contacts_guard();
revoke execute on function public.profile_contacts_guard() from public, anon, authenticated, service_role;

-- A published profile must have a phone (replaces the guard from the profiles migration).
-- Un perfil publicado debe tener teléfono (reemplaza la guarda de la migración de perfiles).
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
-- SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================

-- Rates and contacts: own / admin read, nobody writes through the API.
-- Tarifas y contactos: lectura propia / admin, nadie escribe por la API.
do $$
declare
  t text;
begin
  foreach t in array array['profile_therapy_rates', 'profile_contacts'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format($p$create policy %I on public.%I for select to authenticated
      using (exists (select 1 from public.therapist_profiles tp
                     where tp.id = profile_id and tp.person_id = (select public.current_person_id())))$p$,
      t || '_select_own', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_admin()))',
      t || '_select_admin', t);
  end loop;
end
$$;

-- app_settings: public keys readable by any logged-in user; admin reads all and changes only `value`.
-- app_settings: claves públicas legibles por cualquier usuario con sesión; el admin lee todas y cambia solo `value`.
alter table public.app_settings enable row level security;
grant select on public.app_settings to authenticated;
grant update (value) on public.app_settings to authenticated;
create policy app_settings_select_public on public.app_settings
  for select to authenticated using (is_public);
create policy app_settings_select_admin on public.app_settings
  for select to authenticated using ((select public.is_admin()));
create policy app_settings_update_admin on public.app_settings
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
