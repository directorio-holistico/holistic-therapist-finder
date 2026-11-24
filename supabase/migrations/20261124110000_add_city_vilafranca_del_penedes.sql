-- Add the city "Vilafranca del Penedès" under the region "Cataluña" (a therapist asked for it and it was not in the catalog).
-- Agrega la ciudad "Vilafranca del Penedès" bajo la región "Cataluña" (un terapeuta la pidió y no estaba en el catálogo).
--
-- Idempotent and without fixed ids: the language and the levels are found by code, the region by its Spanish name.
-- Idempotente y sin ids fijos: el idioma y los niveles se buscan por código, la región por su nombre en español.
-- It stops with an error if the region is missing or ambiguous, instead of doing nothing silently.
-- Se detiene con error si la región falta o es ambigua, en vez de no hacer nada en silencio.
-- Catalog data only: no tables, policies or grants are touched. / Solo datos de catálogo: no se tocan tablas, políticas ni permisos.

begin;

do $$
declare
  v_es      integer := (select id from public.languages where code = 'es');
  v_region  integer;
  v_count   integer;
  v_city    integer;
begin
  select count(*), min(l.id) into v_count, v_region
    from public.locations l
    join public.location_levels ll on ll.id = l.level_id and ll.code = 'region'
    join public.location_translations t on t.location_id = l.id and t.language_id = v_es
   where t.name = 'Cataluña' and l.is_active;
  if v_count <> 1 then
    raise exception 'expected exactly 1 active region named Cataluña, found %', v_count;
  end if;

  if not exists (
    select 1 from public.locations c
    join public.location_translations ct on ct.location_id = c.id and ct.language_id = v_es
    where c.parent_id = v_region and ct.name = 'Vilafranca del Penedès'
  ) then
    insert into public.locations (level_id, parent_id, sort_order, is_active)
    select ll.id, v_region, 0, true from public.location_levels ll where ll.code = 'city'
    returning id into v_city;
    insert into public.location_translations (location_id, language_id, name) values (v_city, v_es, 'Vilafranca del Penedès');
  end if;
end $$;

commit;
