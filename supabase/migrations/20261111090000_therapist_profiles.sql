-- Therapist profiles (live version) and their simple link tables. SECURITY CHANGE: 5 tables, 2 functions, 2 triggers.
-- Perfiles de terapeuta (versión vigente) y sus tablas de vínculo. CAMBIO DE SEGURIDAD: 5 tablas, 2 funciones, 2 triggers.
--
-- Rules applied / Reglas aplicadas:
--  * The therapist NEVER writes the live profile: every change is a revision approved by an admin
--    (profile_revisions, a later commit). So these tables have NO INSERT/UPDATE/DELETE grant.
--    El terapeuta NUNCA escribe el perfil vigente: todo cambio es una revisión que aprueba un admin
--    (profile_revisions, commit posterior). Estas tablas NO tienen permiso de escritura.
--  * Privilege fields (status_id, approved_at, status_reason, person_id) are also protected by a trigger,
--    so even a future write grant or policy added by mistake cannot let an API role change them.
--    Los campos de privilegio también los protege un trigger: aunque un permiso o política futura se
--    agregue por error, un rol de la API no puede cambiarlos.
--  * Read access / Lectura:  anon: nothing (public profiles come later through two security_invoker views).
--    authenticated: only their own profile and its link rows. admin: everything.
--    anon: nada (los perfiles públicos llegan después por dos vistas security_invoker).
--    authenticated: solo su perfil y sus vínculos. admin: todo.

-- current_person_id(): the person record of the logged-in user (null if none). SECURITY DEFINER so policies
-- can use it without depending on the RLS of `people`. Fixed search_path, read only.
-- current_person_id(): la ficha de la persona con sesión (nula si no tiene). SECURITY DEFINER para que las
-- políticas no dependan de la RLS de `people`. search_path fijo, solo lectura.
create function public.current_person_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p.id from public.people p where p.auth_user_id = auth.uid() and p.erased_at is null
$$;
revoke execute on function public.current_person_id() from public, anon, service_role;
grant execute on function public.current_person_id() to authenticated;

create table public.therapist_profiles (
  id                  uuid primary key default gen_random_uuid(),
  person_id           uuid not null unique references public.people (id) on delete cascade,
  status_id           smallint not null references public.profile_statuses (id) on delete restrict,
  location_id         integer references public.locations (id) on delete restrict,
  zone                text check (zone = btrim(zone) and char_length(zone) between 1 and 80),
  headline            text check (headline = btrim(headline) and char_length(headline) between 1 and 280),
  practice_start_year smallint check (practice_start_year between 1900 and 2100),
  photo_path          text check (char_length(photo_path) between 1 and 300),
  approved_at         timestamptz,
  status_reason       text check (char_length(status_reason) between 1 and 500),
  created_at          timestamptz not null default now()
);
create index therapist_profiles_location_idx on public.therapist_profiles (location_id);
create index therapist_profiles_status_idx on public.therapist_profiles (status_id);
comment on table public.therapist_profiles is
  'Live (public) version of a therapist profile; one per person / Versión vigente del perfil; una por persona.';

create table public.profile_therapies (
  profile_id      uuid     not null references public.therapist_profiles (id) on delete cascade,
  therapy_id      integer  not null references public.therapies (id) on delete restrict,
  session_minutes smallint check (session_minutes between 5 and 480),
  primary key (profile_id, therapy_id)
);
create index profile_therapies_therapy_idx on public.profile_therapies (therapy_id);
comment on table public.profile_therapies is 'Therapies of a profile; approximate session length per therapy / Terapias del perfil; duración aproximada por terapia.';

create table public.profile_languages (
  profile_id  uuid     not null references public.therapist_profiles (id) on delete cascade,
  language_id smallint not null references public.languages (id) on delete restrict,
  primary key (profile_id, language_id)
);

create table public.profile_service_modes (
  profile_id      uuid     not null references public.therapist_profiles (id) on delete cascade,
  service_mode_id smallint not null references public.service_modes (id) on delete restrict,
  primary key (profile_id, service_mode_id)
);

create table public.profile_session_formats (
  profile_id        uuid     not null references public.therapist_profiles (id) on delete cascade,
  session_format_id smallint not null references public.session_formats (id) on delete restrict,
  primary key (profile_id, session_format_id)
);

-- Guard trigger / Trigger de guarda
--  1) API roles (anon, authenticated) cannot insert profiles nor change privilege fields (checked first).
--  2) The base location must be a city.  3) A published profile needs approved_at and a location.
--  1) Los roles de la API no insertan perfiles ni cambian campos de privilegio (se revisa primero).
--  2) La ubicación base debe ser una ciudad.  3) Un perfil publicado necesita approved_at y ubicación.
create function public.therapist_profiles_guard()
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
  if status_code = 'published' and (new.approved_at is null or new.location_id is null) then
    raise exception 'a published profile needs approved_at and a location' using errcode = '23514';
  end if;

  return new;
end
$$;

create trigger therapist_profiles_guard
  before insert or update on public.therapist_profiles
  for each row execute function public.therapist_profiles_guard();

revoke execute on function public.therapist_profiles_guard() from public, anon, authenticated, service_role;

-- ============================================================================
-- SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================

alter table public.therapist_profiles enable row level security;
grant select on public.therapist_profiles to authenticated;
create policy therapist_profiles_select_own on public.therapist_profiles
  for select to authenticated
  using (person_id = (select public.current_person_id()));
create policy therapist_profiles_select_admin on public.therapist_profiles
  for select to authenticated
  using ((select public.is_admin()));

do $$
declare
  t text;
begin
  foreach t in array array['profile_therapies', 'profile_languages', 'profile_service_modes', 'profile_session_formats'] loop
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
