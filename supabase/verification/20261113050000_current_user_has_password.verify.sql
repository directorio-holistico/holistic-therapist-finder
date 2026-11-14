-- Read-only checks for the REAL project after applying 20261113050000 / Solo lectura, proyecto REAL.
-- 1) Expected / Esperado: 1 row | security_definer = t | anon_can_execute = f | authenticated_can_execute = t.
select p.proname, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'current_user_has_password';
-- 2) The inference check (never prints a hash): a login created by email link and never given a password must show
--    never_set_password = t. Expected today / Esperado hoy: caminodocedoce@gmail.com -> t.
--    La verificación de la inferencia (nunca muestra el hash): un acceso creado por enlace y sin contraseña debe dar t.
select u.email, (coalesce(u.encrypted_password, '') = '') as never_set_password
from auth.users u order by u.created_at;
