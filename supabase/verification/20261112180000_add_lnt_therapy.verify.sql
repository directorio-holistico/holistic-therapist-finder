-- Read-only checks for the REAL project after applying 20261112180000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: 1 row for the LNT therapy, active; 14 active therapies in total (13 + LNT); 24 therapies in all.
select t.id, t.code, t.sort_order, t.is_active, tt.name
from public.therapies t
join public.therapy_translations tt on tt.therapy_id = t.id
where t.code = 'lnt_schwiderski';
select count(*) filter (where is_active) as active_therapies, count(*) as all_therapies from public.therapies;
