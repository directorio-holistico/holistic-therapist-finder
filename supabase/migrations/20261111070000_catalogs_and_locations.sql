-- Catalogs and location hierarchy (Phase 1). SECURITY CHANGE: creates 14 tables with RLS and grants.
-- Catálogos y jerarquía de ubicaciones (Fase 1). CAMBIO DE SEGURIDAD: crea 14 tablas con RLS y permisos.
--
-- Rules applied / Reglas aplicadas:
--  * Catalogs are TABLES with an id, never enums or fixed CHECK lists (glossary: therapy, location).
--    Los catálogos son TABLAS con id, nunca enums ni listas CHECK fijas.
--  * Every table: RLS enabled + explicit GRANT + policies, all in this same migration.
--    Cada tabla: RLS activada + GRANT explícito + políticas, todo en esta misma migración.
--  * Read access (listed in docs/data-model.md, section "Catalog access"):
--      anon + authenticated: only ACTIVE rows of the public catalogs (needed by the search form
--      and, later, by the public views, which use security_invoker).
--      authenticated only: statuses, roles, contact types (internal).
--    Lectura: anon y authenticated ven solo filas ACTIVAS de los catálogos públicos; los catálogos
--    internos (estados, roles, tipos de contacto) solo los lee authenticated.
--  * Writes: NO policy for anon or authenticated, so they are denied (RLS + no INSERT/UPDATE/DELETE grant).
--    Catalogs change through migrations. Admin write policies come with the admin panel (they need
--    the people/person_roles tables, which do not exist yet). This is stricter than the 4-policy rule
--    and is a deliberate, temporary deviation.
--    Escrituras: SIN política ni permiso para anon/authenticated: quedan denegadas. Los catálogos
--    cambian por migración. Las políticas de escritura del admin llegan con el panel de administración
--    (necesitan people/person_roles, que todavía no existen). Es más estricto que la regla de 4
--    políticas y es una desviación deliberada y temporal.
--  * service_role gets no grants here (least privilege); it receives them when a server feature needs them.
--    service_role no recibe permisos acá (mínimo privilegio); los recibe cuando una función de servidor los necesite.
--
-- Display labels of the small catalogs live in the UI dictionary, keyed by `code`; only therapies and
-- locations have translation tables.
-- Las etiquetas de los catálogos chicos viven en el diccionario de la interfaz, por `code`; solo las
-- terapias y las ubicaciones tienen tabla de traducciones.

-- ============================================================================
-- 1. Small catalogs / Catálogos chicos
-- ============================================================================

create table public.languages (
  id          smallint generated always as identity primary key,
  code        text not null unique check (code ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  native_name text not null check (native_name = btrim(native_name) and char_length(native_name) between 1 and 60),
  sort_order  smallint not null default 0,
  is_active   boolean not null default true
);
comment on table public.languages is 'Languages (interface and attention) / Idiomas (interfaz y de atención). code = BCP 47.';

create table public.currencies (
  id          smallint generated always as identity primary key,
  code        text not null unique check (code ~ '^[A-Z]{3}$'),
  minor_units smallint not null check (minor_units between 0 and 3),
  sort_order  smallint not null default 0,
  is_active   boolean not null default true
);
comment on table public.currencies is 'Currencies, ISO 4217 / Monedas, ISO 4217. minor_units = decimals (CLP = 0).';

create table public.contact_types (
  id                 smallint generated always as identity primary key,
  code               text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  is_required        boolean not null default false,
  is_private         boolean not null default true,
  sort_order         smallint not null default 0,
  is_active          boolean not null default true
);
comment on table public.contact_types is
  'Contact types / Tipos de contacto. is_required: the therapist must provide it. is_private: shown only behind "Ver contacto".';

create table public.service_modes (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.service_modes is 'in_person / remote (presencial / a distancia).';

create table public.session_formats (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.session_formats is 'individual / group. "Both" = the two rows / "Ambos" = las dos filas.';

create table public.rate_audiences (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.rate_audiences is 'Who a rate is for / A quién va dirigida la tarifa: own_country, other_countries.';

create table public.profile_statuses (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.profile_statuses is 'Life cycle of a published profile / Ciclo de vida del perfil.';

create table public.revision_statuses (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.revision_statuses is 'Life cycle of a profile revision / Ciclo de vida de una revisión de perfil.';

create table public.roles (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.roles is 'Roles: therapist, admin / Roles: terapeuta, administrador.';

create table public.location_levels (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  depth      smallint not null unique check (depth between 1 and 5),
  is_active  boolean not null default true
);
comment on table public.location_levels is
  'Hierarchy levels / Niveles de la jerarquía. depth 1 = country (país), 2 = region (región), 3 = city (ciudad).';

-- ============================================================================
-- 2. Therapies / Terapias
-- ============================================================================

create table public.therapies (
  id         integer generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table public.therapies is 'Therapy catalog / Catálogo de terapias. Names live in therapy_translations.';

create table public.therapy_translations (
  therapy_id  integer  not null references public.therapies (id) on delete cascade,
  language_id smallint not null references public.languages (id) on delete restrict,
  name        text     not null check (name = btrim(name) and char_length(name) between 1 and 120),
  primary key (therapy_id, language_id)
);
create unique index therapy_translations_name_uniq on public.therapy_translations (language_id, lower(name));
comment on table public.therapy_translations is 'Therapy names per language / Nombres de terapia por idioma.';

-- ============================================================================
-- 3. Locations / Ubicaciones (country > region > city)
-- ============================================================================

create table public.locations (
  id                  integer generated always as identity primary key,
  level_id            smallint not null references public.location_levels (id) on delete restrict,
  parent_id           integer references public.locations (id) on delete restrict,
  iso_code            text check (iso_code ~ '^[A-Z]{2}$'),
  default_currency_id smallint references public.currencies (id) on delete restrict,
  sort_order          smallint not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  check (id is distinct from parent_id)
);
create unique index locations_iso_code_uniq on public.locations (iso_code) where iso_code is not null;
create index locations_parent_idx on public.locations (parent_id);
create index locations_level_idx on public.locations (level_id);
comment on table public.locations is
  'Country > region > city. Only countries have iso_code and default_currency_id / Solo los países tienen iso_code y moneda por defecto.';

create table public.location_translations (
  location_id integer  not null references public.locations (id) on delete cascade,
  language_id smallint not null references public.languages (id) on delete restrict,
  name        text     not null check (name = btrim(name) and char_length(name) between 1 and 120),
  primary key (location_id, language_id)
);
comment on table public.location_translations is 'Location names per language / Nombres de ubicación por idioma.';

-- Hierarchy guard: a country has no parent; every other level has a parent exactly one level above.
-- iso_code and default_currency_id belong to countries only.
-- Guarda de jerarquía: un país no tiene padre; los demás niveles tienen un padre un nivel arriba.
-- iso_code y default_currency_id son solo de países.
create function public.locations_check_hierarchy()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  own_depth    smallint;
  parent_depth smallint;
begin
  select depth into own_depth from public.location_levels where id = new.level_id;

  if own_depth = 1 then
    if new.parent_id is not null then
      raise exception 'a country cannot have a parent location' using errcode = '23514';
    end if;
    if new.iso_code is null then
      raise exception 'a country needs an iso_code' using errcode = '23514';
    end if;
  else
    if new.parent_id is null then
      raise exception 'a region or city needs a parent location' using errcode = '23514';
    end if;
    select l.level_id into strict parent_depth
      from public.locations l where l.id = new.parent_id;
    select depth into parent_depth from public.location_levels where id = parent_depth;
    if parent_depth <> own_depth - 1 then
      raise exception 'parent must be exactly one level above (parent depth %, own depth %)', parent_depth, own_depth
        using errcode = '23514';
    end if;
    if new.iso_code is not null or new.default_currency_id is not null then
      raise exception 'only countries have iso_code and default_currency_id' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

create trigger locations_hierarchy
  before insert or update of level_id, parent_id, iso_code, default_currency_id on public.locations
  for each row execute function public.locations_check_hierarchy();

-- ============================================================================
-- 4. Reference data every environment needs / Datos de referencia que todo ambiente necesita
--    (Test/sample therapies and locations are NOT here: see supabase/seed/dev-seed.sql)
--    (Las terapias y ubicaciones de ejemplo NO están acá: ver supabase/seed/dev-seed.sql)
-- ============================================================================

insert into public.languages (code, native_name, sort_order) values
  ('es', 'Español', 1), ('en', 'English', 2), ('pt', 'Português', 3),
  ('fr', 'Français', 4), ('it', 'Italiano', 5), ('de', 'Deutsch', 6);

insert into public.currencies (code, minor_units, sort_order) values
  ('ARS', 2, 1), ('CLP', 0, 2), ('MXN', 2, 3), ('EUR', 2, 4), ('USD', 2, 5);

insert into public.contact_types (code, is_required, is_private, sort_order) values
  ('phone', true, true, 1), ('email', false, true, 2), ('website', false, false, 3);

insert into public.service_modes (code, sort_order) values ('in_person', 1), ('remote', 2);
insert into public.session_formats (code, sort_order) values ('individual', 1), ('group', 2);
insert into public.rate_audiences (code, sort_order) values ('own_country', 1), ('other_countries', 2);

insert into public.profile_statuses (code, sort_order) values
  ('unpublished', 1), ('published', 2), ('paused', 3), ('suspended', 4), ('erased', 5);
insert into public.revision_statuses (code, sort_order) values
  ('draft', 1), ('pending_review', 2), ('approved', 3), ('rejected', 4), ('discarded', 5);
insert into public.roles (code, sort_order) values ('therapist', 1), ('admin', 2);
insert into public.location_levels (code, depth) values ('country', 1), ('region', 2), ('city', 3);

-- ============================================================================
-- 5. SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================

-- 5.1 Public catalogs: anon and authenticated read ACTIVE rows (authenticated reads all, for the future admin).
-- 5.1 Catálogos públicos: anon y authenticated leen filas ACTIVAS (authenticated lee todas, para el futuro admin).
do $$
declare
  t text;
begin
  foreach t in array array[
    'languages', 'currencies', 'service_modes', 'session_formats', 'rate_audiences',
    'location_levels', 'therapies', 'locations'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('create policy %I on public.%I for select to anon using (is_active)',
                   t || '_select_anon', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)',
                   t || '_select_authenticated', t);
  end loop;
end
$$;

-- Translation tables: visible when the parent row is active (anon) / all rows (authenticated).
-- Tablas de traducción: visibles si la fila padre está activa (anon) / todas (authenticated).
alter table public.therapy_translations enable row level security;
grant select on public.therapy_translations to anon, authenticated;
create policy therapy_translations_select_anon on public.therapy_translations
  for select to anon
  using (exists (select 1 from public.therapies t where t.id = therapy_id and t.is_active));
create policy therapy_translations_select_authenticated on public.therapy_translations
  for select to authenticated using (true);

alter table public.location_translations enable row level security;
grant select on public.location_translations to anon, authenticated;
create policy location_translations_select_anon on public.location_translations
  for select to anon
  using (exists (select 1 from public.locations l where l.id = location_id and l.is_active));
create policy location_translations_select_authenticated on public.location_translations
  for select to authenticated using (true);

-- 5.2 Internal catalogs: authenticated only. anon gets no grant at all.
-- 5.2 Catálogos internos: solo authenticated. anon no recibe ningún permiso.
do $$
declare
  t text;
begin
  foreach t in array array['contact_types', 'profile_statuses', 'revision_statuses', 'roles'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)',
                   t || '_select_authenticated', t);
  end loop;
end
$$;

-- The hierarchy trigger function is not callable by API roles (baseline default privileges already
-- revoke it; stated here so the intent is explicit and survives a baseline change).
-- La función del trigger no la ejecutan los roles de la API (los permisos por defecto de la migración
-- base ya lo quitan; se declara acá para que la intención sea explícita).
revoke execute on function public.locations_check_hierarchy() from public, anon, authenticated, service_role;
