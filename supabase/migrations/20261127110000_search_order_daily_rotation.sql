-- Main page order: without any filter, inside pin, photo and current prices the order ROTATES once a day. Replaces the "newest first"
-- rule of 20261127100000. SECURITY CHANGE (public search function), but only its ORDER BY changes.
-- Orden de la página principal: sin ningún filtro, dentro de fijado, foto y precios al día el orden ROTA una vez por día. Reemplaza la
-- regla "más reciente primero" de 20261127100000. CAMBIO DE SEGURIDAD (función pública de búsqueda), pero solo cambia su ORDER BY.
--
-- Rules / Reglas:
--   * Unfiltered search: pin, photo, current prices, then md5(profile id + today's date in Argentina). Stable all day, new order tomorrow.
--     Búsqueda sin filtros: fijado, foto, precios al día, luego md5(id del perfil + fecha de hoy en Argentina). Estable todo el día.
--   * Any filter: unchanged (oldest approval first). / Con cualquier filtro: sin cambios (aprobación más antigua primero).
--   * Same signature and result columns; grants stated again (anon only). / Misma firma y columnas; permisos repetidos (solo anon).
--   * No table, column, view, policy or data changes. / Sin cambios de tablas, columnas, vistas, políticas ni datos.

create or replace function public.search_profiles(
  p_therapy_id   integer default null,
  p_location_id  integer default null,
  p_service_mode text    default null,
  p_limit        integer default 20,
  p_offset       integer default 0)
returns table (
  result_group smallint, total_count bigint,
  profile_id uuid, display_name text, photo_path text, headline text, zone text, approved_at timestamptz,
  city_id integer, city_name text, region_id integer, region_name text, country_id integer, country_name text, country_iso text,
  therapy_ids integer[], therapy_names text[], service_modes text[], session_formats text[], languages text[], rates_from jsonb,
  rates_confirmed_at timestamptz, rates_current boolean, is_pinned boolean, therapy_short_names text[])
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
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_offset is null or p_offset not between 0 and 10000 then
    raise exception 'offset must be between 0 and 10000' using errcode = '22023';
  end if;
  if p_therapy_id is not null and not exists (select 1 from public.therapies t where t.id = p_therapy_id and t.is_active) then
    raise exception 'unknown therapy' using errcode = '22023';
  end if;
  if p_service_mode is not null and not exists (select 1 from public.service_modes m where m.code = p_service_mode and m.is_active) then
    raise exception 'unknown service mode' using errcode = '22023';
  end if;
  if p_location_id is not null then
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
  end if;

  return query
  with base as (
    -- the modes that count are those of the SEARCHED therapy; with "any therapy", those of the whole profile
    -- las modalidades que cuentan son las de la terapia BUSCADA; con "cualquier terapia", las de todo el perfil
    select c.*,
      case when p_therapy_id is null then coalesce(c.service_modes, '{}')
           else coalesce((select array_agg(m.code) from public.profile_therapy_service_modes x
                          join public.service_modes m on m.id = x.service_mode_id and m.is_active
                          where x.profile_id = c.profile_id and x.therapy_id = p_therapy_id), '{}')
      end as therapy_modes
    from public.public_profile_cards c
    where p_therapy_id is null or c.therapy_ids @> array[p_therapy_id]
  ), filtered as (
    select b.* from base b
    where p_service_mode is null or p_service_mode = any (b.therapy_modes)
  ), grouped as (
    select b.*,
      case
        when p_location_id is null then 1                                    -- anywhere: everyone is in the main group
        when p_location_id in (b.city_id, b.region_id, b.country_id) then 1  -- a country search ends here for every profile of that country
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.therapy_modes)
             and b.country_id = loc_country then 2
        when p_service_mode is distinct from 'in_person' and 'remote' = any (b.therapy_modes) then 3
      end as g
    from filtered b
  )
  select g.g::smallint, count(*) over (),
         g.profile_id, g.display_name, g.photo_path, g.headline, g.zone, g.approved_at,
         g.city_id, g.city_name, g.region_id, g.region_name, g.country_id, g.country_name, g.country_iso,
         g.therapy_ids, g.therapy_names, g.service_modes, g.session_formats, g.languages, g.rates_from,
         g.rates_confirmed_at, g.rates_current, g.is_pinned, g.therapy_short_names
  from grouped g
  where g.g is not null
  -- Order inside a group (owner decision 27/11/2026): the site-owner pin, then a photo, then current prices, then a DAILY
  -- ROTATION. WITHOUT any filter (no therapy, no place, no mode: the main page) the rotation is a hash of the profile id and
  -- today's date in Argentina: the same all day (so paging never repeats or skips anyone) and different tomorrow. With ANY
  -- filter the key is null, so it ties and the old rule decides (oldest approval first).
  -- Orden dentro del grupo (decisión del titular, 27/11/2026): el perfil fijado del sitio, luego foto, luego precios al día,
  -- luego una ROTACIÓN DIARIA. SIN ningún filtro (sin terapia, lugar ni modalidad: la página principal) la rotación es un hash
  -- del id del perfil y la fecha de hoy en Argentina: igual todo el día (así la paginación nunca repite ni saltea a nadie) y
  -- distinta mañana. Con CUALQUIER filtro la clave es null, así empatan y decide la regla anterior (aprobación más antigua).
  order by g.g, g.is_pinned desc, (g.photo_path is not null) desc, g.rates_current desc,
           (case when p_therapy_id is null and p_location_id is null and p_service_mode is null
                 then md5(g.profile_id::text || ((now() at time zone 'America/Argentina/Buenos_Aires')::date)::text) end),
           g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;

revoke execute on function public.search_profiles(integer, integer, text, integer, integer) from public, authenticated, service_role;
grant execute on function public.search_profiles(integer, integer, text, integer, integer) to anon;
