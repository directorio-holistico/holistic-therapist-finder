-- Starter cities: present, under the right region and country, no duplicates, visible to visitors (anon).
-- Ciudades iniciales: presentes, bajo la región y el país correctos, sin duplicados, visibles para los visitantes (anon).
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
declare
  es smallint := (select id from public.languages where code = 'es');
  c record;
  n integer;
begin
  for c in select * from (values
    ('AR', 'Río Negro', 'Cinco Saltos'), ('AR', 'Córdoba', 'Córdoba'), ('AR', 'Santa Fe', 'Rosario'), ('AR', 'Mendoza', 'Mendoza'),
    ('MX', 'Ciudad de México', 'Ciudad de México'), ('MX', 'Jalisco', 'Guadalajara'), ('MX', 'Nuevo León', 'Monterrey'), ('MX', 'Yucatán', 'Mérida'),
    ('ES', 'Comunidad de Madrid', 'Madrid'), ('ES', 'Cataluña', 'Barcelona'), ('ES', 'Comunidad Valenciana', 'Valencia'), ('ES', 'Andalucía', 'Sevilla')
  ) as v(iso, region, city) loop
    select count(*) into n
      from public.locations l
      join public.location_translations lt on lt.location_id = l.id and lt.language_id = es and lt.name = c.city
      join public.locations r on r.id = l.parent_id
      join public.location_translations rt on rt.location_id = r.id and rt.language_id = es and rt.name = c.region
      join public.locations p on p.id = r.parent_id and p.iso_code = c.iso
      where l.level_id = (select id from public.location_levels where code = 'city') and l.is_active;
    if n <> 1 then raise exception 'city % (% / %) must exist exactly once, found %', c.city, c.iso, c.region, n; end if;
  end loop;
end
$$;

-- Visitors (anon) read the cities / Los visitantes (anon) leen las ciudades.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.locations where level_id = (select id from public.location_levels where code = 'city')) < 12 then
    raise exception 'anon must see the 12 starter cities';
  end if;
  if (select count(*) from public.location_translations where name in ('Cinco Saltos', 'Rosario', 'Mérida', 'Sevilla')) < 4 then
    raise exception 'anon cannot read city names';
  end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: starter cities are present and visible to visitors / ciudades iniciales presentes y visibles para los visitantes'
