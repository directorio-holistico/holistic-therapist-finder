-- Initial therapy catalog: complete, consistent, and only the active ones reach visitors.
-- Catálogo inicial de terapias: completo, consistente, y a los visitantes llegan solo las activas.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

do $$
begin
  if (select count(*) from public.therapies) <> 23 then raise exception 'the catalog must have 23 therapies'; end if;
  if (select count(*) from public.therapies where is_active) <> 13 then raise exception 'exactly 13 therapies must be active'; end if;
  -- every therapy has its Spanish name / toda terapia tiene su nombre en español
  if exists (select 1 from public.therapies t
             where not exists (select 1 from public.therapy_translations tt
                               join public.languages l on l.id = tt.language_id
                               where tt.therapy_id = t.id and l.code = 'es')) then
    raise exception 'a therapy has no Spanish name';
  end if;
  -- the internal code of another system must not be in the catalog / el código interno de otro sistema no debe estar
  if exists (select 1 from public.therapy_translations where name ~* '^lnt$') then
    raise exception 'internal name found in the catalog';
  end if;
end
$$;

-- Visitors (anon) see the 13 active therapies with names, and none of the hidden ones.
-- Los visitantes (anon) ven las 13 terapias activas con nombre, y ninguna de las ocultas.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.therapies) <> 13 then raise exception 'anon must see exactly the 13 active therapies'; end if;
  if (select count(*) from public.therapy_translations) <> 13 then raise exception 'anon must see exactly 13 therapy names'; end if;
  if exists (select 1 from public.therapy_translations where name in ('Homeopatía', 'Osteopatía', 'Quiropráctica', 'Suplementos Dietéticos')) then
    raise exception 'anon can see a hidden therapy';
  end if;
  if not exists (select 1 from public.therapy_translations where name = 'Reiki') then raise exception 'anon cannot see Reiki'; end if;
end
$$;
reset role;
reset session authorization;

rollback;
\echo 'OK: therapy catalog is complete and hidden ones stay hidden / catalogo de terapias completo y las ocultas siguen ocultas'
