-- DEMO profiles: the seed loads 6 coherent fictitious profiles, visitors see them, loading twice is refused and the
-- removal script leaves nothing behind (and never touches a real person). All inside a transaction that rolls back.
-- Perfiles DEMO: el seed carga 6 perfiles ficticios coherentes, los visitantes los ven, cargar dos veces se rechaza y el
-- script de borrado no deja nada (y nunca toca a una persona real). Todo en una transacción que se revierte.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

-- a REAL-looking person that must survive the removal / una persona "real" que debe sobrevivir al borrado
insert into public.people (id, full_name, email) values ('10000000-0000-0000-0000-000000000022', 'Persona Real Prueba', 'real22@example.test');

\ir ../demo/seed-demo.sql

do $$
declare
  lnt integer := (select id from public.therapies where code = 'lnt_schwiderski');
begin
  if (select count(*) from public.therapist_profiles tp join public.people p on p.id = tp.person_id where p.email like '%@demo.invalid') <> 6 then
    raise exception 'expected 6 DEMO profiles'; end if;
  -- marker on both name fields / marca en los dos nombres
  if exists (select 1 from public.therapist_profiles tp join public.people p on p.id = tp.person_id
             where p.email like '%@demo.invalid' and (tp.display_name not like '[DEMO] %' or p.full_name not like '[DEMO] %')) then
    raise exception 'a DEMO profile without the [DEMO] marker'; end if;
  -- 2 per country / 2 por país
  if exists (select 1 from (
        select pc.iso_code, count(*) n
        from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
        join public.locations city on city.id = tp.location_id join public.locations reg on reg.id = city.parent_id
        join public.locations pc on pc.id = reg.parent_id group by 1) x where x.n <> 2)
     or (select count(distinct pc.iso_code)
         from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
         join public.locations city on city.id = tp.location_id join public.locations reg on reg.id = city.parent_id
         join public.locations pc on pc.id = reg.parent_id) <> 3 then
    raise exception 'DEMO profiles must be 2 per country in AR, MX, ES'; end if;
  -- all offer LNT plus exactly one other therapy, and the 6 second therapies are different / todos LNT + 1 distinta
  if exists (select 1 from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
             where (select count(*) from public.profile_therapies t where t.profile_id = tp.id) <> 2
                or not exists (select 1 from public.profile_therapies t where t.profile_id = tp.id and t.therapy_id = lnt)) then
    raise exception 'each DEMO profile must offer LNT plus exactly one more therapy'; end if;
  if (select count(distinct t.therapy_id) from public.profile_therapies t
      join public.therapist_profiles tp on tp.id = t.profile_id join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
      where t.therapy_id <> lnt) <> 6 then
    raise exception 'the 6 second therapies must be different'; end if;
  -- price states: 2 current, 2 expired, 2 without prices / tarifas: 2 al día, 2 vencidas, 2 sin
  if (select count(*) from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
      where tp.rates_confirmed_at > now() - interval '6 months'
        and exists (select 1 from public.profile_therapy_rates r where r.profile_id = tp.id)) <> 2
     or (select count(*) from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
         where tp.rates_confirmed_at <= now() - interval '6 months'
           and exists (select 1 from public.profile_therapy_rates r where r.profile_id = tp.id)) <> 2
     or (select count(*) from public.therapist_profiles tp join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
         where not exists (select 1 from public.profile_therapy_rates r where r.profile_id = tp.id)) <> 2 then
    raise exception 'price states must be 2 current, 2 expired, 2 without prices'; end if;
end
$$;

-- Visitors (anon) find them through the search and cannot read contacts / Los visitantes (anon) los encuentran y no leen contactos.
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  if (select count(*) from public.search_profiles(
        (select id from public.therapies where code = 'lnt_schwiderski'),
        (select id from public.locations where iso_code = 'AR'), null, 50, 0)) <> 5 then
    raise exception 'anon search for LNT in AR must return 2 local + 3 remote DEMO profiles';
  end if;
  if (select count(*) from public.profile_contacts) <> 0 then raise exception 'anon must not read contacts'; end if;
end
$$;
reset role;
reset session authorization;

-- Loading twice is refused (the error is expected and printed below) / Cargar dos veces se rechaza (el error es esperado)
\set ON_ERROR_STOP off
savepoint second_load;
\ir ../demo/seed-demo.sql
rollback to savepoint second_load;
\set ON_ERROR_STOP on
do $$
begin
  if (select count(*) from public.people where email like '%@demo.invalid') <> 6 then
    raise exception 'a second load must change nothing (still 6 DEMO people)'; end if;
end
$$;

\ir ../demo/remove-demo.sql

do $$
begin
  if exists (select 1 from public.people where email like '%@demo.invalid') then raise exception 'DEMO people remain'; end if;
  if exists (select 1 from public.therapist_profiles tp where not exists (select 1 from public.people p where p.id = tp.person_id)) then
    raise exception 'orphan profiles'; end if;
  if (select count(*) from public.therapist_profiles where display_name like '[DEMO] %') <> 0 then raise exception 'DEMO profiles remain'; end if;
  if not exists (select 1 from public.people where id = '10000000-0000-0000-0000-000000000022') then
    raise exception 'removal touched a real person'; end if;
end
$$;

rollback;
\echo 'OK: DEMO seed and removal behave as designed / el seed y el borrado DEMO funcionan como se diseno'
