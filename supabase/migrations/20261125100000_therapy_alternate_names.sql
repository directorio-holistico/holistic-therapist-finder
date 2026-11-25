-- Therapy names with a well-known alternate name or spelling, written "Spanish name / alternate name" (owner decision of 25/11/2026).
-- Nombres de terapia con otro nombre o grafía muy conocida, escritos "nombre en español / otro nombre" (decisión del titular del 25/11/2026).
--
-- Why / Por qué: the type-ahead matches the beginning of each word of the name, so a visitor who types "biof" or "access bars" finds the therapy
-- only if that word is in the name. Rule (glossary): at most 2 names separated by " / ", Spanish first; the card uses the short name.
-- El buscador compara el comienzo de cada palabra del nombre; si el visitante escribe "biof" o "access bars" solo encuentra la terapia si esa
-- palabra está en el nombre. Regla (glosario): máximo 2 nombres separados por " / ", el español primero; la tarjeta usa el nombre corto.
--
-- Reference data only (Spanish rows of therapy_translations): no tables, grants, policies or functions are touched. NOT a security change.
-- Solo datos de referencia (filas en español de therapy_translations): no se tocan tablas, permisos, políticas ni funciones. NO es cambio de seguridad.
-- Found by therapy code, never by id; it stops with an error if any of the 8 therapies is missing. Safe to run twice.
-- Se busca por código de terapia, nunca por id; se detiene con error si falta alguna de las 8 terapias. Se puede correr dos veces.
-- "Constelaciones" is NOT changed here: it was renamed on 17/11/2026 on purpose. / "Constelaciones" NO se cambia acá: se renombró a propósito el 17/11/2026.

do $$
declare
  v_es      integer := (select id from public.languages where code = 'es');
  v_updated integer;
begin
  with new_names (code, full_name, short_name) as (
    values
      ('biofeedback',        'Biorretroalimentación / Biofeedback',     'Biorretroalimentación'),
      ('biodecoding',        'BioDecodificación / Biodescodificación',  'BioDecodificación'),
      ('access_bars',        'Barras de Access / Access Bars',          'Barras de Access'),
      ('qigong',             'Qi Gong / Qigong',                        'Qi Gong'),
      ('tai_chi',            'Tai Chi / Taichi',                        'Tai Chi'),
      ('chiropractic',       'Quiropraxia / Quiropráctica',             'Quiropraxia'),
      ('thai_massage',       'Masaje tailandés / Masaje Thai',          'Masaje tailandés'),
      ('cupping_moxibustion','Ventosas y moxibustión / Cupping',        'Ventosas y moxa')
  ), done as (
    update public.therapy_translations tt
       set name = n.full_name, short_name = n.short_name
      from new_names n
      join public.therapies t on t.code = n.code
     where tt.therapy_id = t.id and tt.language_id = v_es
    returning tt.therapy_id
  )
  select count(*) into v_updated from done;

  if v_updated <> 8 then
    raise exception 'expected to rename 8 therapies, renamed %', v_updated;
  end if;
end
$$;
