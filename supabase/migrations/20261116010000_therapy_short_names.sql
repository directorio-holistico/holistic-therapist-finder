-- Short name of a therapy (for cards). SECURITY CHANGE: it changes a public view and the public search function.
-- Nombre corto de una terapia (para las tarjetas). CAMBIO DE SEGURIDAD: cambia una vista pública y la función pública de búsqueda.
--
-- Rules / Reglas:
--   * therapy_translations gets a nullable "short_name" (1-40 characters, trimmed). Null = the card uses the full name.
--     therapy_translations recibe un "short_name" opcional (1-40 caracteres, sin espacios en los bordes). Null = la tarjeta usa el nombre completo.
--   * No new table, grant or policy: therapy_translations is already readable by anon and authenticated for ACTIVE therapies
--     (table-level SELECT and policy from 20261111070000) and nobody can write to it. The short name is a catalog name, not
--     personal data. / Sin tabla, permiso ni política nuevos: therapy_translations ya la leen anon y authenticated para
--     terapias ACTIVAS (SELECT de tabla y política de 20261111070000) y nadie puede escribirla. El nombre corto es un nombre
--     de catálogo, no un dato personal.
--   * public_profile_cards: same columns + "therapy_short_names" at the END (same order as therapy_names: by therapy id).
--     public_profile_cards: mismas columnas + "therapy_short_names" AL FINAL (mismo orden que therapy_names: por id de terapia).
--     public_profile_detail does not change (its columns were fixed when it was created).
--     public_profile_detail no cambia (sus columnas quedaron fijas al crearla).
--   * search_profiles also returns the new column. A function cannot change its result columns in place, so it is dropped and
--     created again with the SAME signature and the SAME grants (anon only), as 20261112170000 did.
--     search_profiles devuelve también la columna nueva. Una función no puede cambiar sus columnas de resultado en el lugar,
--     por eso se elimina y se crea de nuevo con la MISMA firma y los MISMOS permisos (solo anon), como hizo 20261112170000.
--   * Data: only LNT gets a short name now (the owner's example). The others stay null and show their full name until the
--     owner decides. / Datos: por ahora solo LNT recibe nombre corto (el ejemplo del titular). Las demás quedan en null y
--     muestran su nombre completo hasta que el titular decida.

-- 1. Column / Columna
alter table public.therapy_translations
  add column short_name text
  check (short_name is null or (short_name = btrim(short_name) and char_length(short_name) between 1 and 40));
comment on column public.therapy_translations.short_name is 'Short name for cards / Nombre corto para tarjetas. Null = use name.';

-- 2. Data: LNT / Dato: LNT
update public.therapy_translations tt
   set short_name = 'LNT®'
 where tt.therapy_id = (select t.id from public.therapies t where t.code = 'lnt_schwiderski')
   and tt.language_id = (select l.id from public.languages l where l.code = 'es');

-- 3. Public view / Vista pública
create or replace view public.public_profile_cards with (security_invoker = true) as
select
  tp.id                      as profile_id,
  tp.display_name,
  tp.photo_path,
  tp.headline,
  tp.zone,
  tp.approved_at,
  tp.location_id             as city_id,
  city_t.name                as city_name,
  anc.region_id,
  region_t.name              as region_name,
  anc.country_id,
  country_t.name             as country_name,
  country.iso_code           as country_iso,
  coalesce(th.therapy_ids, '{}')    as therapy_ids,
  coalesce(th.therapy_names, '{}')  as therapy_names,
  coalesce(sm.codes, '{}')   as service_modes,
  coalesce(sf.codes, '{}')   as session_formats,
  coalesce(lg.codes, '{}')   as languages,
  coalesce(rt.rates_from, '{}'::jsonb) as rates_from,
  -- new columns go at the END (create or replace view cannot insert columns in the middle)
  -- las columnas nuevas van AL FINAL (create or replace view no permite insertar columnas en el medio)
  tp.rates_confirmed_at,
  (rt.rates_from is not null and rt.rates_from <> '{}'::jsonb
   and tp.rates_confirmed_at is not null
   and tp.rates_confirmed_at >= now() - make_interval(months => public.rates_validity_months())) as rates_current,
  tp.is_pinned,
  -- new column at the END / columna nueva al FINAL: short name of each therapy, same order as therapy_names (by id)
  coalesce(th.therapy_short_names, '{}') as therapy_short_names
from public.therapist_profiles tp
cross join lateral (select l.id from public.languages l where l.code = 'es') es
left join lateral (
  with recursive up as (
    select l.id, l.parent_id, l.level_id from public.locations l where l.id = tp.location_id
    union all
    select l.id, l.parent_id, l.level_id from public.locations l join up on l.id = up.parent_id
  )
  select max(up.id) filter (where ll.code = 'region')  as region_id,
         max(up.id) filter (where ll.code = 'country') as country_id
  from up join public.location_levels ll on ll.id = up.level_id
) anc on true
left join public.location_translations city_t on city_t.location_id = tp.location_id and city_t.language_id = es.id
left join public.location_translations region_t on region_t.location_id = anc.region_id and region_t.language_id = es.id
left join public.locations country on country.id = anc.country_id
left join public.location_translations country_t on country_t.location_id = anc.country_id and country_t.language_id = es.id
left join lateral (
  select array_agg(t.id order by t.id) as therapy_ids, array_agg(coalesce(tt.name, t.code) order by t.id) as therapy_names,
         array_agg(coalesce(tt.short_name, tt.name, t.code) order by t.id) as therapy_short_names
  from public.profile_therapies pt
  join public.therapies t on t.id = pt.therapy_id and t.is_active
  left join public.therapy_translations tt on tt.therapy_id = t.id and tt.language_id = es.id
  where pt.profile_id = tp.id
) th on true
left join lateral (
  -- union of the modes of all the (active) therapies / unión de las modalidades de todas las terapias (activas)
  select array_agg(m.code order by m.sort_order, m.id) as codes
  from public.service_modes m
  where m.is_active and exists (
    select 1 from public.profile_therapy_service_modes x
    join public.therapies t on t.id = x.therapy_id and t.is_active
    where x.profile_id = tp.id and x.service_mode_id = m.id)
) sm on true
left join lateral (
  -- union of the formats of all the (active) therapies / unión de los formatos de todas las terapias (activas)
  select array_agg(f.code order by f.sort_order, f.id) as codes
  from public.session_formats f
  where f.is_active and exists (
    select 1 from public.profile_therapy_session_formats x
    join public.therapies t on t.id = x.therapy_id and t.is_active
    where x.profile_id = tp.id and x.session_format_id = f.id)
) sf on true
left join lateral (
  select array_agg(l.code order by l.sort_order, l.id) as codes
  from public.profile_languages x join public.languages l on l.id = x.language_id and l.is_active
  where x.profile_id = tp.id
) lg on true
left join lateral (
  -- "from" rate per audience: the lowest amount, with its currency (one currency per audience in a profile)
  -- tarifa "desde" por audiencia: el monto más bajo, con su moneda (una moneda por audiencia en el perfil)
  select jsonb_object_agg(x.audience, jsonb_build_object('amount', x.min_amount, 'currency', x.currency)) as rates_from
  from (
    select a.code as audience, c.code as currency, min(r.amount) as min_amount
    from public.profile_therapy_rates r
    join public.therapies t on t.id = r.therapy_id and t.is_active
    join public.rate_audiences a on a.id = r.rate_audience_id and a.is_active
    join public.currencies c on c.id = r.currency_id
    where r.profile_id = tp.id
    group by a.code, c.code
  ) x
) rt on true
where public.is_published_profile(tp.id);

-- 4. Search function (same signature, same grants) / Función de búsqueda (misma firma, mismos permisos)
drop function public.search_profiles(integer, integer, text, integer, integer);

create function public.search_profiles(
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
  -- Order inside a group (owner decision 12/11/2026): the site-owner pin, then current prices, then a photo, then the
  -- oldest approval. Orden dentro del grupo (decisión del titular, 12/11/2026): el perfil fijado del sitio, luego precios
  -- al día, luego foto, luego la aprobación más antigua.
  order by g.g, g.is_pinned desc, g.rates_current desc, (g.photo_path is not null) desc, g.approved_at, g.profile_id
  limit p_limit offset p_offset;
end
$$;

revoke execute on function public.search_profiles(integer, integer, text, integer, integer) from public, authenticated, service_role;
grant execute on function public.search_profiles(integer, integer, text, integer, integer) to anon;
