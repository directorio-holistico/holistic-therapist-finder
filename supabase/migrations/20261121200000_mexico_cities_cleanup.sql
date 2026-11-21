-- Removes 11 places of Mexico that the GeoNames load (20261121190000) took as cities but are housing developments, industrial
-- parks, ex-haciendas or neighbourhood names. Owner decision 21/11/2026: "if somebody asks for one, we add it".
-- Quita 11 lugares de México que la carga de GeoNames (20261121190000) tomó por ciudades pero son fraccionamientos, parques
-- industriales, ex-haciendas o nombres de barrio. Decisión del titular (21/11/2026): "si alguien lo pide, lo agregamos".
--
-- Rules / Reglas:
--   * Data only: no table, permission or function is created or changed. / Solo datos: no crea ni cambia tablas, permisos ni funciones.
--   * A place is deleted ONLY if nothing points to it: it checks every foreign key that references locations (profiles,
--     requests, searches, children...) and the "location_id" inside revision payloads. A place in use is kept and reported.
--     Un lugar se borra SOLO si nada lo usa: revisa todas las claves foráneas que apuntan a locations (perfiles, pedidos,
--     búsquedas, hijos...) y el "location_id" dentro de los payloads de revisión. Un lugar en uso se conserva y se avisa.
--   * Idempotent: running it again finds nothing to delete. / Idempotente: ejecutarla de nuevo no encuentra nada que borrar.
--   * Note: re-running 20261121190000 on a database would load these places again; it is only run once, on an empty load.
--     Ojo: volver a correr 20261121190000 en una base los cargaría de nuevo; se corre una sola vez, sobre una carga vacía.

do $$
declare
  v_es      smallint := (select id from public.languages where code = 'es');
  v_country integer;
  v_rec     record;
  v_fk      record;
  v_used    boolean;
  v_found   boolean;
  v_deleted integer := 0;
  v_kept    integer := 0;
begin
  select id into v_country from public.locations where level_id = 1 and iso_code = 'MX';
  if v_country is null then raise exception 'Missing country MX / Falta el país MX'; end if;

  for v_rec in
    select c.id, ct.name as city, rt.name as region
      from (values
      ('Hidalgo', 'Campestre Villas del Álamo'),
      ('Hidalgo', 'Parque Urbano Napateco'),
      ('Estado de México', 'Conjunto Urbano la Loma I'),
      ('Estado de México', 'Ex-Hacienda de Xalpa'),
      ('Estado de México', 'Ex-Hacienda Santa Inés'),
      ('Estado de México', 'Ex-Rancho San Dimas'),
      ('Michoacán', 'Conjunto Habitacional Villas del Pedregal'),
      ('Nuevo León', 'Parque Industrial Ciudad Mitras'),
      ('Nuevo León', 'Villas de Alcalá'),
      ('Guanajuato', 'Villas de Irapuato'),
      ('Guerrero', 'San José Ixtapa (Barrio Viejo)')
      ) as w(region, city)
      join public.location_translations rt on rt.language_id = v_es and rt.name = w.region
      join public.locations r on r.id = rt.location_id and r.level_id = 2 and r.parent_id = v_country
      join public.location_translations ct on ct.language_id = v_es and ct.name = w.city
      join public.locations c on c.id = ct.location_id and c.level_id = 3 and c.parent_id = r.id
  loop
    v_used := false;
    for v_fk in
      select c.conrelid::regclass::text as tbl, a.attname as col
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and c.confrelid = 'public.locations'::regclass
         and cardinality(c.conkey) = 1 and c.conrelid <> 'public.location_translations'::regclass
    loop
      execute format('select exists (select 1 from %s where %I = $1)', v_fk.tbl, v_fk.col) into v_found using v_rec.id;
      if v_found then v_used := true; end if;
    end loop;
    if to_regclass('public.profile_revisions') is not null then
      select exists (select 1 from public.profile_revisions where payload ->> 'location_id' = v_rec.id::text) into v_found;
      if v_found then v_used := true; end if;
    end if;

    if v_used then
      v_kept := v_kept + 1;
      raise notice 'Kept, in use / Se conserva, está en uso: % (%)', v_rec.city, v_rec.region;
    else
      delete from public.location_translations where location_id = v_rec.id;
      delete from public.locations where id = v_rec.id;
      v_deleted := v_deleted + 1;
    end if;
  end loop;

  raise notice 'Deleted / borradas: %, kept / conservadas: %', v_deleted, v_kept;
end $$;
