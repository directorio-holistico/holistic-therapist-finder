-- Removes EVERY DEMO record (twin of seed-demo.sql). Run before opening to the public.
-- Quita TODO lo DEMO (gemelo de seed-demo.sql). Correr antes de abrir al público.
--
--  * Deletes people that have BOTH marks: email @demo.invalid AND full_name starting with "[DEMO] ". A real person can
--    never match (demo.invalid cannot be registered). Profiles, therapies, rates, contacts and reveal counters go with
--    them by cascade; moderation and report rows keep their record with the profile link set to null.
--    Borra personas con AMBAS marcas: mail @demo.invalid Y nombre que empieza con "[DEMO] ". Una persona real no puede
--    coincidir. Perfiles, terapias, tarifas, contactos y contadores se van en cascada; moderación y denuncias conservan
--    su registro con el vínculo al perfil en nulo.
--  * Refuses if the count is not what it expects (0 to 6) / Se niega si la cantidad no es la esperada (0 a 6).
--  * Does NOT touch cities (they are real) nor the unmet-search log. / NO toca las ciudades (son reales) ni las búsquedas sin resultado.

do $$
declare
  n integer;
begin
  select count(*) into n from public.people where email like '%@demo.invalid' and full_name like '[DEMO] %';
  if n > 6 then raise exception 'more than 6 DEMO people (%): refusing, check by hand / más de 6 personas DEMO: se niega', n; end if;
  delete from public.people where email like '%@demo.invalid' and full_name like '[DEMO] %';
  raise notice 'DEMO removed: % people / DEMO quitado: % personas', n, n;
end
$$;
