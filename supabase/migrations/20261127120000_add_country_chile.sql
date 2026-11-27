-- Country Chile: the country, its 16 regions and 36 main cities (catalog data only; no table, permission, policy or function is created or changed).
-- Reverses the decision of 12/11/2026 ("Chile is left out for now"): the owner approved Chile on 27/11/2026.
-- Idempotent and without fixed ids: language, levels and currency are found by code; a region or city is skipped when its parent already has one with the
-- same Spanish name. It stops with an error if the language, a level or the CLP currency is missing, instead of loading half.
-- The list of cities is short and written by hand on purpose (no bulk load, so no GeoNames credit is needed). A city that is missing can still be requested
-- by the therapist ("my city is not in the list") and added by hand, as before.
-- País Chile: el país, sus 16 regiones y 36 ciudades principales (solo datos de catálogo; no se crea ni cambia ninguna tabla, permiso, política ni función).
-- Revierte la decisión del 12/11/2026 ("Chile queda afuera por ahora"): el titular aprobó Chile el 27/11/2026.
-- Idempotente y sin ids fijos: idioma, niveles y moneda se buscan por código; una región o ciudad se saltea si su padre ya tiene otra con el mismo nombre en
-- español. Se detiene con error si falta el idioma, un nivel o la moneda CLP, en vez de cargar a medias.
-- La lista de ciudades es corta y escrita a mano a propósito (sin carga masiva, así que no hace falta el crédito de GeoNames). Una ciudad que falte se puede
-- pedir igual ("mi ciudad no está en la lista") y cargar a mano, como hasta ahora.

do $$
declare
  v_es        smallint := (select id from public.languages where code = 'es');
  v_lv_ctry   smallint := (select id from public.location_levels where code = 'country');
  v_lv_region smallint := (select id from public.location_levels where code = 'region');
  v_lv_city   smallint := (select id from public.location_levels where code = 'city');
  v_clp       smallint := (select id from public.currencies where code = 'CLP');
  v_country   integer;
  v_region    integer;
  v_exists    integer;
  v_id        integer;
  v_r         record;
  v_c         text;
  v_n         smallint := 0;
begin
  if v_es is null or v_lv_ctry is null or v_lv_region is null or v_lv_city is null or v_clp is null then
    raise exception 'missing language, location level or CLP currency';
  end if;

  select id into v_country from public.locations where iso_code = 'CL';
  if v_country is null then
    insert into public.locations (level_id, iso_code, default_currency_id) values (v_lv_ctry, 'CL', v_clp) returning id into v_country;
    insert into public.location_translations (location_id, language_id, name) values (v_country, v_es, 'Chile');
  end if;

  for v_r in select * from (values
    ('Arica y Parinacota', array['Arica']),
    ('Tarapacá', array['Iquique', 'Alto Hospicio']),
    ('Antofagasta', array['Antofagasta', 'Calama']),
    ('Atacama', array['Copiapó']),
    ('Coquimbo', array['La Serena', 'Coquimbo', 'Ovalle']),
    ('Valparaíso', array['Valparaíso', 'Viña del Mar', 'Quilpué', 'Villa Alemana', 'San Antonio', 'Quillota']),
    ('Metropolitana de Santiago', array['Santiago', 'Puente Alto', 'Maipú', 'Las Condes', 'Providencia', 'Ñuñoa', 'La Florida']),
    ('Libertador General Bernardo O''Higgins', array['Rancagua']),
    ('Maule', array['Talca', 'Curicó']),
    ('Ñuble', array['Chillán']),
    ('Biobío', array['Concepción', 'Talcahuano', 'Los Ángeles']),
    ('La Araucanía', array['Temuco']),
    ('Los Ríos', array['Valdivia']),
    ('Los Lagos', array['Puerto Montt', 'Osorno', 'Puerto Varas']),
    ('Aysén', array['Coyhaique']),
    ('Magallanes', array['Punta Arenas'])
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
