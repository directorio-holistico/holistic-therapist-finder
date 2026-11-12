-- Read-only: how many DEMO records exist and what the public sees. / Solo lectura: cuántos registros DEMO hay.
select (select count(*) from public.people where email like '%@demo.invalid') as demo_people,
       (select count(*) from public.therapist_profiles tp join public.people p on p.id = tp.person_id
         where p.email like '%@demo.invalid') as demo_profiles,
       (select count(*) from public.people where email not like '%@demo.invalid') as real_people;
select p.email, tp.display_name, c.name_city as city, tp.rates_confirmed_at is not null as has_prices
from public.therapist_profiles tp
join public.people p on p.id = tp.person_id and p.email like '%@demo.invalid'
cross join lateral (select lt.name as name_city from public.location_translations lt
                    join public.languages g on g.id = lt.language_id and g.code = 'es'
                    where lt.location_id = tp.location_id) c
order by p.email;
