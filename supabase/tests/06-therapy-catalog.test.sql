-- Initial therapy catalog: complete, consistent, and only the active ones reach visitors.
-- Catálogo inicial de terapias: completo, consistente, y a los visitantes llegan solo las activas.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
begin
  if (select count(*) from public.therapies) <> 40 then raise exception 'the catalog must have 40 therapies'; end if;
  if (select count(*) from public.therapies where is_active) <> 34 then raise exception 'exactly 34 therapies must be active'; end if;
  -- every therapy has its Spanish name / toda terapia tiene su nombre en español
  if exists (select 1 from public.therapies t
             where not exists (select 1 from public.therapy_translations tt
                               join public.languages l on l.id = tt.language_id
                               where tt.therapy_id = t.id and l.code = 'es')) then
    raise exception 'a therapy has no Spanish name';
  end if;
  -- LNT is in the catalog under its public name, active, with a Spanish name / LNT está con su nombre público, activa y con nombre en español
  if not exists (select 1 from public.therapies t join public.therapy_translations tt on tt.therapy_id = t.id
                 where t.code = 'lnt_schwiderski' and t.is_active and tt.name = 'LNT® - La Nueva Terapia - Método Schwiderski') then
    raise exception 'LNT therapy missing, inactive or misnamed';
  end if;
  -- the internal code of another system must not be in the catalog / el código interno de otro sistema no debe estar
  if exists (select 1 from public.therapy_translations where name ~* '^lnt$') then
    raise exception 'internal name found in the catalog';
  end if;
end
$$;

-- Visitors (anon) see the 34 active therapies with names, and none of the hidden ones.
-- Los visitantes (anon) ven las 34 terapias activas con nombre, y ninguna de las ocultas.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.therapies) <> 34 then raise exception 'anon must see exactly the 34 active therapies'; end if;
  if (select count(*) from public.therapy_translations) <> 34 then raise exception 'anon must see exactly 34 therapy names'; end if;
  if exists (select 1 from public.therapy_translations where name in ('Osteopatía', 'Suplementos Dietéticos', 'Toque Terapéutico')) then
    raise exception 'anon can see a hidden therapy';
  end if;
  -- activated on 23/11/2026 (Psicoanálisis y psicoterapia psicoanalítica) / activada el 23/11/2026
  if not exists (select 1 from public.therapy_translations where name = 'Psicoanálisis y psicoterapia psicoanalítica') then raise exception 'anon cannot see psychoanalysis'; end if;
  if not exists (select 1 from public.therapy_translations where name = 'Reiki') then raise exception 'anon cannot see Reiki'; end if;
  if not exists (select 1 from public.therapy_translations where name like 'LNT%') then raise exception 'anon cannot see LNT'; end if;
  if not exists (select 1 from public.therapy_translations where name = 'Constelaciones') then raise exception 'anon cannot see Constelaciones'; end if;
  if (select count(*) from public.therapy_translations where name in ('Masaje tailandés', 'Masaje con calor y elementos', 'Ventosas y moxibustión', 'Shiatsu', 'Masajes Terapéuticos', 'Reflexología')) <> 6 then raise exception 'anon cannot see the massage therapies'; end if;
  -- reactivated on 19/11/2026 (Acupuntura, Homeopatía, Fitoterapia) and added the same day (Terapia vibracional, Facilitador de procesos sociales)
  -- reactivadas el 19/11/2026 (Acupuntura, Homeopatía, Fitoterapia) y agregadas ese día (Terapia vibracional, Facilitador de procesos sociales)
  if (select count(*) from public.therapy_translations where name in ('Acupuntura (Medicina Tradicional China)', 'Homeopatía', 'Fitoterapia', 'Terapia vibracional', 'Facilitador de procesos sociales')) <> 5 then raise exception 'anon cannot see the reactivated or new therapies'; end if;
  -- added on 20/11/2026 (Focusing, Reimpronta del origen, Retiros y viajes)
  -- agregadas el 20/11/2026 (Focusing, Reimpronta del origen, Retiros y viajes)
  if (select count(*) from public.therapy_translations where name in ('Focusing', 'Reimpronta del origen', 'Retiros y viajes')) <> 3 then raise exception 'anon cannot see Focusing, Reimpronta del origen or Retiros y viajes'; end if;
  -- added or reactivated on 20/11/2026 (Yoga, Tai Chi, Qi Gong, Ayurveda, Quiropraxia); the old combined name and the old name of Quiropraxia are gone
  -- agregadas o reactivadas el 20/11/2026 (Yoga, Tai Chi, Qi Gong, Ayurveda, Quiropraxia); el nombre combinado viejo y el nombre viejo de Quiropraxia ya no están
  if (select count(*) from public.therapy_translations where name in ('Yoga', 'Tai Chi', 'Qi Gong', 'Ayurveda', 'Quiropraxia')) <> 5 then raise exception 'anon cannot see Yoga, Tai Chi, Qi Gong, Ayurveda or Quiropraxia'; end if;
  if exists (select 1 from public.therapy_translations where name in ('Yoga y Tai Chi / Qi Gong', 'Quiropráctica')) then raise exception 'an old name (combined yoga or Quiropráctica) is still there'; end if;
  if exists (select 1 from public.therapy_translations where name = 'Constelaciones familiares') then raise exception 'the old name Constelaciones familiares is still there'; end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: therapy catalog is complete and hidden ones stay hidden / catalogo de terapias completo y las ocultas siguen ocultas'
