-- Search and unmet demand. SECURITY CHANGE: 1 table, 3 functions (2 callable by visitors), 1 setting.
-- Búsqueda y demanda no cubierta. CAMBIO DE SEGURIDAD: 1 tabla, 3 funciones (2 invocables solo por visitantes anon), 1 ajuste.
--
-- Rules applied / Reglas aplicadas (model v03, section 4.2 / modelo v03, sección 4.2):
--  * A search needs a therapy and a location (country, region or city); the service mode is an optional filter.
--    Una búsqueda necesita terapia y ubicación (país, región o ciudad); el modo de atención es un filtro opcional.
--  * Result groups / Grupos de resultados (column result_group):
--      1 = profiles inside the chosen location / perfiles dentro de la ubicación elegida;
--      2 = remote profiles in the same country but outside the chosen place ("Otras ciudades"); only when a region
--          or a city was chosen / a distancia, mismo país pero fuera del lugar elegido; solo si se eligió región o ciudad;
--      3 = remote profiles in other countries ("Otros países") / a distancia, de otros países.
--    With the in-person filter there are no groups 2 and 3. / Con el filtro presencial no hay grupos 2 ni 3.
--    The codes 'in_person' and 'remote' of service_modes carry this business rule. / Los códigos 'in_person' y 'remote'
--    de service_modes llevan esta regla de negocio.
--  * Stable order: group, approval date, id. No ordering by price. / Orden estable: grupo, fecha de aprobación, id.
--  * search_profiles reads ONLY the public view, with the caller's own permissions (security invoker), so a visitor can
--    never get more than the view shows. / search_profiles lee SOLO la vista pública, con los permisos de quien llama.
--  * Searches with no result are recorded by log_search, counted per day and per (therapy, location, mode): no IP, no
--    identifier, no row per visit. log_search records only if the search truly has no result.
--    Las búsquedas sin resultado las registra log_search, contadas por día y por (terapia, ubicación, modo): sin IP, sin
--    identificador, sin una fila por visita. Solo registra si la búsqueda de verdad no tiene resultados.
--  * Retention: configurable, 12 months by default (decided by the owner on 11/11/2026).
--    Retención: configurable, 12 meses por defecto (decidido por el dueño el 11/11/2026).
--  * NOT here yet: rate limiting by origin (needs an ADR: the database cannot know the visitor's address when the
--    website server makes the call). / TODAVÍA NO: límite de pedidos por origen (necesita un ADR).

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
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('retention_unmet_searches_months', '12', false,
   'Months to keep the unmet-search counters (1-120) / Meses que se conservan los contadores de búsquedas sin resultado (1-120)');

-- ============================================================================
-- 2. unmet_searches (daily counters, no personal data) / contadores diarios, sin datos personales
-- ============================================================================
create table public.unmet_searches (
  id              bigint generated always as identity primary key,
  therapy_id      integer  not null references public.therapies (id) on delete restrict,
  location_id     integer  not null references public.locations (id) on delete restrict,
  service_mode_id smallint references public.service_modes (id) on delete restrict,
  day             date     not null,
  searches_count  integer  not null default 1 check (searches_count between 1 and 1000000),
  unique nulls not distinct (therapy_id, location_id, service_mode_id, day)
);
create index unmet_searches_day_idx on public.unmet_searches (day);
comment on table public.unmet_searches is
  'Searches with no result, counted per day (UTC) and per therapy, location and mode. No IP, no identifier / Búsquedas sin resultado, contadas por día (UTC), terapia, ubicación y modo. Sin IP ni identificador.';

-- SECURITY: RLS + GRANT. Only the admin reads; nobody writes through the API (log_search does).
-- SEGURIDAD: RLS + GRANT. Solo el admin lee; nadie escribe por la API (lo hace log_search).
alter table public.unmet_searches enable row level security;
grant select on public.unmet_searches to authenticated;
create policy unmet_searches_select_admin on public.unmet_searches
  for select to authenticated using ((select public.is_admin()));

-- ============================================================================
-- 3. search_profiles (security invoker: reads only the public view, with the caller's permissions)
-- ============================================================================
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
  therapy_ids integer[], therapy_names text[], service_modes text[], session_formats text[], languages text[], rates_from jsonb)
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
         g.therapy_ids, g.therapy_names, g.service_modes, g.session_formats, g.languages, g.rates_from
  from grouped g
  where g.g is not null
  order by g.g, g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;
revoke execute on function public.search_profiles(integer, integer, text, integer, integer) from public, authenticated, service_role;
-- anon only: public pages are rendered with the anon role (commit 19); as authenticated the view shows just the caller's own
-- profile, so a search would return partial results. / Solo anon: las páginas públicas usan el rol anon (commit 19); como
-- authenticated la vista muestra solo el perfil propio y la búsqueda daría resultados parciales.
grant execute on function public.search_profiles(integer, integer, text, integer, integer) to anon;

-- ============================================================================
-- 4. log_search: records a search that really had no result (callable by visitors)
-- ============================================================================
-- Returns true when it recorded the search, false when the search has results (nothing recorded).
-- Devuelve true si registró la búsqueda, false si la búsqueda tiene resultados (no se registra nada).
create function public.log_search(p_therapy_id integer, p_location_id integer, p_service_mode text default null)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  mode_id smallint;
  today   date := (now() at time zone 'utc')::date;
begin
  if p_therapy_id is null or p_location_id is null then
    raise exception 'therapy and location are required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.therapies t where t.id = p_therapy_id and t.is_active) then
    raise exception 'unknown therapy' using errcode = '22023';
  end if;
  if not exists (select 1 from public.locations l where l.id = p_location_id and l.is_active) then
    raise exception 'unknown location' using errcode = '22023';
  end if;
  if p_service_mode is not null then
    select m.id into mode_id from public.service_modes m where m.code = p_service_mode and m.is_active;
    if mode_id is null then
      raise exception 'unknown service mode' using errcode = '22023';
    end if;
  end if;

  -- only a search with no result in any group counts as unmet demand
  -- solo una búsqueda sin resultado en ningún grupo cuenta como demanda no cubierta
  if exists (select 1 from public.search_profiles(p_therapy_id, p_location_id, p_service_mode, 1, 0)) then
    return false;
  end if;

  insert into public.unmet_searches as u (therapy_id, location_id, service_mode_id, day)
    values (p_therapy_id, p_location_id, mode_id, today)
    on conflict (therapy_id, location_id, service_mode_id, day)
    do update set searches_count = least(u.searches_count + 1, 1000000);
  return true;
end
$$;
revoke execute on function public.log_search(integer, integer, text) from public, authenticated, service_role;
grant execute on function public.log_search(integer, integer, text) to anon;

-- ============================================================================
-- 5. Retention: purge old counters (for the scheduled job, server only)
-- ============================================================================
create function public.purge_expired_unmet_searches()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  months  integer;
  removed integer;
begin
  select (value::text)::int into months from public.app_settings where key = 'retention_unmet_searches_months';
  if months is null then
    raise exception 'setting retention_unmet_searches_months is missing' using errcode = '23514';
  end if;
  delete from public.unmet_searches
    where day < ((now() at time zone 'utc')::date - make_interval(months => months))::date;
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.purge_expired_unmet_searches() from public, anon, authenticated;
grant execute on function public.purge_expired_unmet_searches() to service_role;
