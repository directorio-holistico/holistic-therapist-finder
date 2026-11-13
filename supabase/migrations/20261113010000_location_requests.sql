-- "My city is not listed" requests. SECURITY CHANGE: 1 table, 1 trigger function, 1 callable function, 8 policies.
-- Pedidos "mi ciudad no está". CAMBIO DE SEGURIDAD: 1 tabla, 1 función de trigger, 1 función invocable, 8 políticas.
--
-- Owner decision (12/11/2026) / Decisión del titular (12/11/2026): a therapist whose city is not in the catalog writes
-- it down (region + city name) so the sign-up is not blocked; the administrator adds the city and links the request.
-- The profile cannot be published without a city (the existing guard), so the city exists by the time it is approved.
-- un terapeuta cuya ciudad no está en el catálogo la escribe (región + nombre) para no frenar el alta; el administrador
-- carga la ciudad y vincula el pedido. El perfil no se publica sin ciudad (guarda existente): al aprobarse, la ciudad ya existe.
--
-- Rules / Reglas:
--  * ONE open request per profile (unique partial index). Changing the city name edits it; it never piles up.
--    UN pedido abierto por perfil (índice único parcial). Cambiar el nombre lo edita; no se acumulan.
--  * The therapist inserts, edits and deletes ONLY the open request of their own profile (column grants + RLS). They cannot
--    touch the resolution columns. Suspended and erased profiles cannot create requests.
--    El terapeuta inserta, edita y borra SOLO el pedido abierto de su perfil (permisos por columna + RLS). No toca las
--    columnas de resolución. Los perfiles suspendidos y eliminados no crean pedidos.
--  * The admin reads all and resolves through resolve_location_request (never by direct UPDATE).
--    El admin lee todos y resuelve con resolve_location_request (nunca con UPDATE directo).
--  * city_name is free text typed by a person: it is shown to the admin only, never publicly, and the audit log keeps
--    column NAMES only. Retention: it lives as long as the profile (it is not personal data by itself).
--    city_name es texto libre escrito por una persona: lo ve solo el admin, nunca se publica, y el registro de auditoría
--    guarda solo NOMBRES de columnas. Retención: dura lo que el perfil (por sí solo no es un dato personal).

create table public.location_requests (
  id                   bigint generated always as identity primary key,
  profile_id           uuid    not null references public.therapist_profiles (id) on delete cascade,
  region_id            integer not null references public.locations (id) on delete restrict,
  city_name            text    not null check (city_name = btrim(city_name) and char_length(city_name) between 2 and 80),
  created_at           timestamptz not null default now(),
  resolved_at          timestamptz,
  resolved_location_id integer references public.locations (id) on delete set null,
  resolved_by_person_id uuid   references public.people (id) on delete set null,
  check (resolved_location_id is null or resolved_at is not null)
);
create unique index location_requests_one_open on public.location_requests (profile_id) where resolved_at is null;
create index location_requests_open_idx on public.location_requests (created_at) where resolved_at is null;
create index location_requests_region_idx on public.location_requests (region_id);
comment on table public.location_requests is
  'City typed by a therapist because it is not in the catalog; the admin adds it and resolves / Ciudad escrita por un terapeuta porque no está en el catálogo; el admin la carga y resuelve.';

-- Guard (SECURITY DEFINER so it can read the profile status even when RLS hides the profile; the RLS policy then refuses
-- foreign profiles with a clear permission error): the region must be an ACTIVE region-level location; a closed request cannot be edited; no requests for
-- suspended or erased profiles. / Guarda (SECURITY DEFINER para leer el estado del perfil aunque RLS lo oculte; la política RLS
-- rechaza luego los perfiles ajenos con un error de permisos claro): la región debe ser una ubicación ACTIVA de nivel región; un pedido cerrado no se edita;
-- sin pedidos para perfiles suspendidos o eliminados.
create function public.location_requests_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  profile_status text;
begin
  if tg_op = 'UPDATE' and old.resolved_at is not null then
    raise exception 'a resolved request cannot be changed' using errcode = '55000';
  end if;
  if tg_op = 'INSERT' then
    select ps.code into strict profile_status
      from public.therapist_profiles tp join public.profile_statuses ps on ps.id = tp.status_id
      where tp.id = new.profile_id;
    if profile_status in ('suspended', 'erased') then
      raise exception 'a % profile cannot request a city', profile_status using errcode = '55000';
    end if;
  end if;
  if tg_op = 'INSERT' or new.region_id is distinct from old.region_id then
    if not exists (select 1 from public.locations l join public.location_levels ll on ll.id = l.level_id
                   where l.id = new.region_id and ll.code = 'region' and l.is_active) then
      raise exception 'the region must be an active region' using errcode = '22023';
    end if;
  end if;
  return new;
end
$$;
create trigger location_requests_guard
  before insert or update on public.location_requests
  for each row execute function public.location_requests_guard();
revoke execute on function public.location_requests_guard() from public, anon, authenticated, service_role;

-- SECURITY: RLS + GRANT + 4 policies for the owner (select, insert, update, delete) + admin read.
-- SEGURIDAD: RLS + GRANT + 4 políticas para el dueño (select, insert, update, delete) + lectura del admin.
alter table public.location_requests enable row level security;
grant select, delete on public.location_requests to authenticated;
grant insert (profile_id, region_id, city_name) on public.location_requests to authenticated;
grant update (region_id, city_name) on public.location_requests to authenticated;

create policy location_requests_select_own on public.location_requests
  for select to authenticated
  using (exists (select 1 from public.therapist_profiles tp
                 where tp.id = profile_id and tp.person_id = (select public.current_person_id())));
create policy location_requests_select_admin on public.location_requests
  for select to authenticated using ((select public.is_admin()));
create policy location_requests_insert_own on public.location_requests
  for insert to authenticated
  with check (exists (select 1 from public.therapist_profiles tp
                      where tp.id = profile_id and tp.person_id = (select public.current_person_id())));
create policy location_requests_update_own_open on public.location_requests
  for update to authenticated
  using (resolved_at is null
         and exists (select 1 from public.therapist_profiles tp
                     where tp.id = profile_id and tp.person_id = (select public.current_person_id())))
  with check (resolved_at is null
              and exists (select 1 from public.therapist_profiles tp
                          where tp.id = profile_id and tp.person_id = (select public.current_person_id())));
create policy location_requests_delete_own_open on public.location_requests
  for delete to authenticated
  using (resolved_at is null
         and exists (select 1 from public.therapist_profiles tp
                     where tp.id = profile_id and tp.person_id = (select public.current_person_id())));

-- Audit: who changed what (names of columns only). / Auditoría: quién cambió qué (solo nombres de columnas).
create trigger audit_location_requests after insert or update or delete on public.location_requests
  for each row execute function public.audit_row_change('id');

-- resolve_location_request: the admin links the request to the city they added. The city must be active, of city level
-- and under the region the therapist chose. SECURITY DEFINER with fixed search_path; only the admin passes.
-- resolve_location_request: el admin vincula el pedido con la ciudad que cargó. La ciudad debe estar activa, ser de nivel
-- ciudad y estar bajo la región que eligió el terapeuta. SECURITY DEFINER con search_path fijo; solo pasa el admin.
create function public.resolve_location_request(p_request_id bigint, p_location_id integer)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  req    public.location_requests%rowtype;
  person uuid := public.current_person_id();
begin
  if person is null or not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  select * into req from public.location_requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if req.resolved_at is not null then
    raise exception 'the request is already resolved' using errcode = '55000';
  end if;
  if not exists (select 1 from public.locations l join public.location_levels ll on ll.id = l.level_id
                 where l.id = p_location_id and ll.code = 'city' and l.is_active and l.parent_id = req.region_id) then
    raise exception 'the city must be an active city under the requested region' using errcode = '22023';
  end if;
  update public.location_requests
     set resolved_at = now(), resolved_location_id = p_location_id, resolved_by_person_id = person
   where id = p_request_id;
end
$$;
revoke execute on function public.resolve_location_request(bigint, integer) from public, anon, service_role;
grant execute on function public.resolve_location_request(bigint, integer) to authenticated;
