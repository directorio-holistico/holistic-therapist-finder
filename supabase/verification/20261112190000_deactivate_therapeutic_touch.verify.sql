-- Read-only checks for the REAL project after applying 20261112190000 / Solo lectura, proyecto REAL.
-- Expected / Esperado: therapeutic_touch inactive; 13 active therapies (12 old + LNT); 24 therapies in all.
select code, is_active from public.therapies where code = 'therapeutic_touch';
select count(*) filter (where is_active) as active_therapies, count(*) as all_therapies from public.therapies;
