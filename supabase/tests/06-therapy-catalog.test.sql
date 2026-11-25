-- Initial therapy catalog: complete, consistent, and only the active ones reach visitors.
-- Catálogo inicial de terapias: completo, consistente, y a los visitantes llegan solo las activas.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
begin
  -- no hard-coded totals: the catalog changes often. The rules are checked and the numbers are read from the catalog.
  -- sin totales fijos: el catálogo cambia seguido. Se comprueban las reglas y los números se leen del catálogo.
  if not exists (select 1 from public.therapies where is_active) then raise exception 'the catalog must have active therapies'; end if;
  -- remember, for the visitor checks below, which therapies are active and which are hidden (transaction-local)
  -- se guarda, para las pruebas del visitante, qué terapias están activas y cuáles ocultas (solo dentro de la transacción)
  perform set_config('test.active_therapies', (select count(*) from public.therapies where is_active)::text, true);
  perform set_config('test.inactive_ids', (select coalesce(string_agg(id::text, ','), '') from public.therapies where not is_active), true);
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

-- Visitors (anon) see exactly the active therapies, each with a name, and none of the hidden ones.
-- Los visitantes (anon) ven exactamente las terapias activas, cada una con nombre, y ninguna de las ocultas.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.therapies) <> current_setting('test.active_therapies')::int then raise exception 'anon must see exactly the active therapies'; end if;
  if exists (select 1 from public.therapies t where not exists (select 1 from public.therapy_translations tt where tt.therapy_id = t.id)) then
    raise exception 'anon sees a therapy without a name';
  end if;
  -- hidden therapies reach visitors neither as therapies nor as names / las ocultas no llegan al visitante ni como terapia ni como nombre
  if exists (select 1 from public.therapies where id = any (string_to_array(nullif(current_setting('test.inactive_ids'), ''), ',')::int[])) then
    raise exception 'anon can see a hidden therapy';
  end if;
  if exists (select 1 from public.therapy_translations where therapy_id = any (string_to_array(nullif(current_setting('test.inactive_ids'), ''), ',')::int[])) then
    raise exception 'anon can see the name of a hidden therapy';
  end if;
  if not exists (select 1 from public.therapy_translations where name = 'Reiki') then raise exception 'anon cannot see Reiki'; end if;
  if not exists (select 1 from public.therapy_translations where name like 'LNT%') then raise exception 'anon cannot see LNT'; end if;
  if not exists (select 1 from public.therapy_translations where name = 'Constelaciones') then raise exception 'anon cannot see Constelaciones'; end if;
  if (select count(*) from public.therapy_translations where name in ('Masaje tailandés / Masaje Thai', 'Masaje con calor y elementos', 'Ventosas y moxibustión / Cupping', 'Shiatsu', 'Masajes Terapéuticos', 'Reflexología')) <> 6 then raise exception 'anon cannot see the massage therapies'; end if;
  -- reactivated on 19/11/2026 (Acupuntura, Homeopatía, Fitoterapia) and added the same day (Terapia vibracional, Facilitador de procesos sociales)
  -- reactivadas el 19/11/2026 (Acupuntura, Homeopatía, Fitoterapia) y agregadas ese día (Terapia vibracional, Facilitador de procesos sociales)
  if (select count(*) from public.therapy_translations where name in ('Acupuntura (Medicina Tradicional China)', 'Homeopatía', 'Fitoterapia', 'Terapia vibracional', 'Facilitador de procesos sociales')) <> 5 then raise exception 'anon cannot see the reactivated or new therapies'; end if;
  -- added on 20/11/2026 (Focusing, Reimpronta del origen, Retiros y viajes)
  -- agregadas el 20/11/2026 (Focusing, Reimpronta del origen, Retiros y viajes)
  if (select count(*) from public.therapy_translations where name in ('Focusing', 'Reimpronta del origen', 'Retiros y viajes')) <> 3 then raise exception 'anon cannot see Focusing, Reimpronta del origen or Retiros y viajes'; end if;
  -- added or reactivated on 20/11/2026 (Yoga, Tai Chi, Qi Gong, Ayurveda, Quiropraxia); the old combined name and the old name of Quiropraxia are gone
  -- agregadas o reactivadas el 20/11/2026 (Yoga, Tai Chi, Qi Gong, Ayurveda, Quiropraxia); el nombre combinado viejo y el nombre viejo de Quiropraxia ya no están
  if (select count(*) from public.therapy_translations where name in ('Yoga', 'Tai Chi / Taichi', 'Qi Gong / Qigong', 'Ayurveda', 'Quiropraxia / Quiropráctica')) <> 5 then raise exception 'anon cannot see Yoga, Tai Chi, Qi Gong, Ayurveda or Quiropraxia'; end if;
  if exists (select 1 from public.therapy_translations where name in ('Yoga y Tai Chi / Qi Gong', 'Quiropráctica')) then raise exception 'an old name (combined yoga or Quiropráctica) is still there'; end if;
  if exists (select 1 from public.therapy_translations where name = 'Constelaciones familiares') then raise exception 'the old name Constelaciones familiares is still there'; end if;
  -- alternate names of 25/11/2026 ("Spanish / alternate"): Biofeedback, Biodescodificación, Access Bars; the short name is what cards show
  -- nombres alternativos del 25/11/2026 ("español / alternativo"): Biofeedback, Biodescodificación, Access Bars; el nombre corto es lo que muestran las tarjetas
  -- Biorretroalimentación is inactive in the local seed (it was activated in production), so it is not counted here
  -- Biorretroalimentación está inactiva en el seed local (se activó en producción), por eso no se cuenta acá
  if (select count(*) from public.therapy_translations where name in ('BioDecodificación / Biodescodificación', 'Barras de Access / Access Bars')) <> 2 then raise exception 'anon cannot see the active therapies with an alternate name'; end if;
  if exists (select 1 from public.therapy_translations where name in ('Biorretroalimentación', 'BioDecodificación', 'Barras de Access', 'Qi Gong', 'Tai Chi', 'Quiropraxia', 'Masaje tailandés', 'Ventosas y moxibustión')) then raise exception 'an old name without its alternate name is still there'; end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: therapy catalog is complete and hidden ones stay hidden / catalogo de terapias completo y las ocultas siguen ocultas'
