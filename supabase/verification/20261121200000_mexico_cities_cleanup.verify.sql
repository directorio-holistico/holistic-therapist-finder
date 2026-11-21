-- Read-only checks for 20261121200000_mexico_cities_cleanup.sql. / Comprobaciones de solo lectura.
-- Expected / esperado: quedan_de_las_11 = 0 (or the ones in use), total_ciudades = 1715, acayucan = 1, ciudades_repetidas = 0
with es as (select id from public.languages where code = 'es'),
mx as (select id from public.locations where level_id = 1 and iso_code = 'MX'),
reg as (select l.id, t.name from public.locations l
          join public.location_translations t on t.location_id = l.id and t.language_id = (select id from es)
         where l.level_id = 2 and l.parent_id = (select id from mx)),
city as (select l.id, l.parent_id, t.name from public.locations l
           join public.location_translations t on t.location_id = l.id and t.language_id = (select id from es)
          where l.level_id = 3 and l.parent_id in (select id from reg))
select jsonb_build_object(
  'total_ciudades', (select count(*) from city),
  'quedan_de_las_11', (select count(*) from city c join reg r on r.id = c.parent_id
      where (r.name, c.name) in (
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
      ('Guerrero', 'San José Ixtapa (Barrio Viejo)'))),
  'acayucan', (select count(*) from city where lower(name) = 'acayucan'),
  'ciudades_repetidas', (select count(*) from (select parent_id, lower(name) from city group by 1, 2 having count(*) > 1) d)
) as verificacion;
