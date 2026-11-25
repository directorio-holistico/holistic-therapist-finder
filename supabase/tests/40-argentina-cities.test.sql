-- Cities of Argentina: loaded, one per name in each province, the capital city stays a single city, and visitors can read them.
-- Ciudades de Argentina: cargadas, una por nombre en cada provincia, la capital sigue siendo una sola ciudad, y los visitantes las pueden leer.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
declare
  v_es   smallint := (select id from public.languages where code = 'es');
  v_city smallint := (select id from public.location_levels where code = 'city');
  v_ar   integer  := (select id from public.locations where iso_code = 'AR' and level_id = (select id from public.location_levels where code = 'country'));
begin
  -- a good part of the country is loaded / buena parte del país está cargada
  if (select count(*) from public.locations l where l.level_id = v_city
        and l.parent_id in (select id from public.locations where parent_id = v_ar)) < 900 then
    raise exception 'Argentina should have at least 900 cities loaded';
  end if;
  -- the places that started this load are there, once each, under the right province
  -- los lugares que motivaron esta carga están, una vez cada uno, bajo la provincia correcta
  if (select count(*) from public.locations c
        join public.location_translations ct on ct.location_id = c.id and ct.language_id = v_es
        join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = v_es
       where c.level_id = v_city and rt.name = 'Buenos Aires'
         and ct.name in ('Olivos', 'Martínez', 'Beccar', 'Villa Ballester', 'Adrogué', 'Pinamar', 'La Plata', 'Mar del Plata')) <> 8 then
    raise exception 'a key city of Buenos Aires is missing or repeated';
  end if;
  -- no repeated name (ignoring accents and capitals) inside one province / ningún nombre repetido (sin tildes ni mayúsculas) dentro de una provincia
  if exists (select 1 from public.locations c
               join public.location_translations ct on ct.location_id = c.id and ct.language_id = v_es
              where c.level_id = v_city and c.parent_id in (select id from public.locations where parent_id = v_ar)
              group by c.parent_id, lower(translate(ct.name, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) having count(*) > 1) then
    raise exception 'a city name is repeated inside a province';
  end if;
  -- CABA (Ciudad Autónoma de Buenos Aires) stays a single city / CABA (Ciudad Autónoma de Buenos Aires) sigue siendo una sola ciudad
  if (select count(*) from public.locations c
        join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = v_es
       where c.level_id = v_city and rt.name = 'CABA') <> 1 then
    raise exception 'CABA must have exactly one city';
  end if;
  -- no Delta islands or streams / sin islas ni arroyos del Delta
  if exists (select 1 from public.locations c
               join public.location_translations ct on ct.location_id = c.id and ct.language_id = v_es
               join public.location_translations rt on rt.location_id = c.parent_id and rt.language_id = v_es
              where rt.name = 'Buenos Aires' and ct.name ~ '^(Arroyo |Boca |Tercera Sección|Forestal )') then
    raise exception 'Delta places should not be loaded';
  end if;
end
$$;

-- Visitors (anon) can read the cities / Los visitantes (anon) pueden leer las ciudades
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.locations l where l.level_id = (select id from public.location_levels where code = 'city')) < 900 then
    raise exception 'anon cannot read the Argentine cities';
  end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: Argentine cities are loaded, unique and readable by visitors / ciudades de Argentina cargadas, unicas y legibles por visitantes'
