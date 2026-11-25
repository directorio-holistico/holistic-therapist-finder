-- Short public name for the region "Ciudad Autónoma de Buenos Aires": "CABA" (cards read "Ciudad de Buenos Aires, CABA, Argentina").
-- Nombre público corto para la región "Ciudad Autónoma de Buenos Aires": "CABA" (las tarjetas dicen "Ciudad de Buenos Aires, CABA, Argentina").
--
-- Idempotent and without fixed ids: the region is found by its Spanish name inside Argentina (old or new name). It stops with an error if
-- there is not exactly one, instead of doing nothing silently. The city "Ciudad de Buenos Aires" and every reference by id stay as they are.
-- Idempotente y sin ids fijos: la región se busca por su nombre en español dentro de Argentina (el viejo o el nuevo). Se detiene con error
-- si no hay exactamente una, en vez de no hacer nada en silencio. La ciudad "Ciudad de Buenos Aires" y toda referencia por id no cambian.
-- Catalog data only: no tables, policies or grants are touched. / Solo datos de catálogo: no se tocan tablas, políticas ni permisos.

do $$
declare
  v_es      integer := (select id from public.languages where code = 'es');
  v_country integer;
  v_region  integer;
  v_count   integer;
begin
  select id into v_country from public.locations
   where iso_code = 'AR' and level_id = (select id from public.location_levels where code = 'country');
  if v_country is null then raise exception 'Missing country AR / Falta el país AR'; end if;

  select count(*), min(l.id) into v_count, v_region
    from public.locations l
    join public.location_translations t on t.location_id = l.id and t.language_id = v_es
   where l.parent_id = v_country
     and l.level_id = (select id from public.location_levels where code = 'region')
     and t.name in ('Ciudad Autónoma de Buenos Aires', 'CABA');
  if v_count <> 1 then
    raise exception 'expected exactly 1 region of Argentina named Ciudad Autónoma de Buenos Aires or CABA, found %', v_count;
  end if;

  update public.location_translations set name = 'CABA'
   where location_id = v_region and language_id = v_es and name <> 'CABA';
end $$;
