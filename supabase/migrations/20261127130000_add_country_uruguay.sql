-- Country Uruguay: the currency UYU, the country, its 19 departments (stored as regions) and 27 main cities (catalog data only; no table, permission, policy or function is created or changed).
-- Owner approved Uruguay and the currency UYU on 27/11/2026. The currency is added because it did not exist in the catalog; it also becomes available in the prices form.
-- Idempotent and without fixed ids: language, levels and currency are found by code; a department or city is skipped when its parent already has one with the same Spanish
-- name. It stops with an error if the language or a level is missing, instead of loading half. The list of cities is short and written by hand on purpose
-- (no bulk load, so no GeoNames credit is needed). A city that is missing can still be requested by the therapist and added by hand, as before.
-- País Uruguay: la moneda UYU, el país, sus 19 departamentos (guardados como regiones) y 27 ciudades principales (solo datos de catálogo; no se crea ni cambia ninguna tabla,
-- permiso, política ni función). El titular aprobó Uruguay y la moneda UYU el 27/11/2026. Se agrega la moneda porque no existía en el catálogo; también pasa a estar
-- disponible en el formulario de precios. Idempotente y sin ids fijos: idioma, niveles y moneda se buscan por código; un departamento o ciudad se saltea si su padre ya
-- tiene otro con el mismo nombre en español. Se detiene con error si falta el idioma o un nivel, en vez de cargar a medias. La lista de ciudades es corta y escrita a mano
-- a propósito (sin carga masiva, así que no hace falta el crédito de GeoNames). Una ciudad que falte se puede pedir igual y cargar a mano, como hasta ahora.

insert into public.currencies (code, minor_units, sort_order)
select 'UYU', 2, 6
where not exists (select 1 from public.currencies where code = 'UYU');

do $$
declare
  v_es        smallint := (select id from public.languages where code = 'es');
  v_lv_ctry   smallint := (select id from public.location_levels where code = 'country');
  v_lv_region smallint := (select id from public.location_levels where code = 'region');
  v_lv_city   smallint := (select id from public.location_levels where code = 'city');
  v_uyu       smallint := (select id from public.currencies where code = 'UYU');
  v_country   integer;
  v_region    integer;
  v_exists    integer;
  v_id        integer;
  v_r         record;
  v_c         text;
  v_n         smallint := 0;
begin
  if v_es is null or v_lv_ctry is null or v_lv_region is null or v_lv_city is null or v_uyu is null then
    raise exception 'missing language, location level or UYU currency';
  end if;

  select id into v_country from public.locations where iso_code = 'UY';
  if v_country is null then
    insert into public.locations (level_id, iso_code, default_currency_id) values (v_lv_ctry, 'UY', v_uyu) returning id into v_country;
    insert into public.location_translations (location_id, language_id, name) values (v_country, v_es, 'Uruguay');
  end if;

  for v_r in select * from (values
    ('Artigas', array['Artigas']),
    ('Canelones', array['Canelones', 'Ciudad de la Costa', 'Las Piedras', 'Pando']),
    ('Cerro Largo', array['Melo']),
    ('Colonia', array['Colonia del Sacramento', 'Carmelo', 'Nueva Helvecia']),
    ('Durazno', array['Durazno']),
    ('Flores', array['Trinidad']),
    ('Florida', array['Florida']),
    ('Lavalleja', array['Minas']),
    ('Maldonado', array['Maldonado', 'Punta del Este', 'San Carlos']),
    ('Montevideo', array['Montevideo']),
    ('Paysandú', array['Paysandú']),
    ('Río Negro', array['Fray Bentos']),
    ('Rivera', array['Rivera']),
    ('Rocha', array['Rocha', 'La Paloma']),
    ('Salto', array['Salto']),
    ('San José', array['San José de Mayo']),
    ('Soriano', array['Mercedes']),
    ('Tacuarembó', array['Tacuarembó']),
    ('Treinta y Tres', array['Treinta y Tres'])
  ) as t(region, cities)
  loop
    v_n := v_n + 1;
    select l.id into v_region
      from public.locations l
      join public.location_translations t on t.location_id = l.id and t.language_id = v_es
     where l.parent_id = v_country and l.level_id = v_lv_region and t.name = v_r.region;
    if v_region is null then
      insert into public.locations (level_id, parent_id, sort_order) values (v_lv_region, v_country, v_n) returning id into v_region;
      insert into public.location_translations (location_id, language_id, name) values (v_region, v_es, v_r.region);
    end if;

    foreach v_c in array v_r.cities loop
      select c.id into v_exists
        from public.locations c
        join public.location_translations ct on ct.location_id = c.id and ct.language_id = v_es
       where c.parent_id = v_region and c.level_id = v_lv_city and ct.name = v_c;
      if v_exists is null then
        insert into public.locations (level_id, parent_id, sort_order) values (v_lv_city, v_region, 0) returning id into v_id;
        insert into public.location_translations (location_id, language_id, name) values (v_id, v_es, v_c);
      end if;
    end loop;
  end loop;
end $$;
