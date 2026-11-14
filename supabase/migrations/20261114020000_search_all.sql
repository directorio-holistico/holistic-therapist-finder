-- Search with "Todos": the therapy and the place become optional in search_profiles.
-- Búsqueda con "Todos": la terapia y el lugar pasan a ser opcionales en search_profiles.
--
-- Rules / Reglas:
--   * p_therapy_id null  = any therapy; the mode filter then uses the modes of ANY therapy of the profile.
--     p_therapy_id null  = cualquier terapia; el filtro de modalidad usa las de CUALQUIER terapia del perfil.
--   * p_location_id null = anywhere in the world; every profile that passes the filters is group 1.
--     p_location_id null = cualquier lugar; todo perfil que pase los filtros es del grupo 1.
--   * A given therapy or place that does not exist is still rejected (22023).
--     Una terapia o lugar que se da y no existe se sigue rechazando (22023).
--   * Same signature, same grants (anon only); security invoker; no new table; no new data exposed
--     (it reads the same public_profile_cards view as before).
--     Misma firma, mismos permisos (solo anon); security invoker; sin tablas nuevas ni datos nuevos expuestos
--     (lee la misma vista public_profile_cards de antes).

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
  rates_confirmed_at timestamptz, rates_current boolean, is_pinned boolean)
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
         g.rates_confirmed_at, g.rates_current, g.is_pinned
  from grouped g
  where g.g is not null
  -- Order inside a group (owner decision 12/11/2026): the site-owner pin, then current prices, then a photo, then the
  -- oldest approval. Orden dentro del grupo (decisión del titular, 12/11/2026): el perfil fijado del sitio, luego precios
  -- al día, luego foto, luego la aprobación más antigua.
  order by g.g, g.is_pinned desc, g.rates_current desc, (g.photo_path is not null) desc, g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;

-- Same signature: the grants stay, but they are repeated here so this file is self-explanatory.
-- Misma firma: los permisos se mantienen, pero se repiten acá para que el archivo se entienda solo.
revoke execute on function public.search_profiles(integer, integer, text, integer, integer) from public, authenticated, service_role;
grant execute on function public.search_profiles(integer, integer, text, integer, integer) to anon;

