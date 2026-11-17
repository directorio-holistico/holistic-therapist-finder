-- Rate limit by origin for sign-in actions and for the unmet-search log (follows ADR-0003).
-- SECURITY CHANGE: 3 settings, 2 functions, and the direct door `log_search` is CLOSED for every API role.
-- Límite de pedidos por origen para las acciones de ingreso y para el registro de búsquedas sin resultado (sigue el ADR-0003).
-- CAMBIO DE SEGURIDAD: 3 ajustes, 2 funciones, y la puerta directa `log_search` queda CERRADA para todos los roles de la API.
--
--  * Why: the website server calls Supabase Auth, so Auth sees the server's address, not the visitor's: its own per-address
--    limits cannot protect each visitor. The server reads the visitor's address, hashes it (HMAC, see src/lib/origin.ts) and
--    asks rate_limit_hit() BEFORE calling Auth. The database only sees 64 hex characters, never an address or an e-mail.
--    Por qué: el servidor de la web llama a Supabase Auth, así que Auth ve la dirección del servidor y no la del visitante:
--    sus límites por dirección no protegen a cada visitante. El servidor lee la dirección, la convierte en hash (HMAC, ver
--    src/lib/origin.ts) y pregunta a rate_limit_hit() ANTES de llamar a Auth. La base solo ve 64 caracteres hexadecimales.
--  * Before: `anon` (public key) could call log_search directly and inflate the unmet-demand counters. After: NO API role runs
--    log_search; the only door is log_search_limited(therapy, place, mode, origin_hash), executable only by service_role.
--    Antes: `anon` (clave pública) podía llamar log_search directo e inflar los contadores de demanda sin cubrir. Ahora:
--    NINGÚN rol de la API ejecuta log_search; la única puerta es log_search_limited(...), solo para service_role.
--  * The count is one atomic statement (INSERT ... ON CONFLICT DO UPDATE ... WHERE hits < limit), like reveal_contact_limited.
--    Over the limit rate_limit_hit returns false (it does not raise): the caller decides what to answer.
--    El conteo es una sola sentencia atómica, como en reveal_contact_limited. Pasado el límite rate_limit_hit devuelve false
--    (no lanza error): quien llama decide qué responder.
--  * Day window = fixed UTC day (up to 2x the limit can pass around midnight; same acceptance as ADR-0003).
--    Ventana = día UTC fijo (cerca de la medianoche pueden pasar hasta 2 veces el límite; igual aceptación que el ADR-0003).
--  * NOT covered here: reading the search (search_profiles shows only public data) is limited by the platform (firewall), not here.
--    NO cubierto acá: la lectura de la búsqueda (search_profiles solo muestra datos públicos) se limita en la plataforma (firewall).

-- ============================================================================
-- 1. Settings / Ajustes
-- ============================================================================
alter table public.app_settings drop constraint app_settings_value_valid;
alter table public.app_settings add constraint app_settings_value_valid check (
  case key
    when 'max_therapies_per_profile'
      then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 10
    when 'review_days_initial' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_update' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'review_days_priority' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'moderation_allow_self_approval' then jsonb_typeof(value) = 'boolean'
    when 'retention_unmet_searches_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_contact_reveals_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_reports_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'retention_erasure_fingerprints_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'reveal_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,5}$' and (value::text)::int between 1 and 10000
    when 'report_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,4}$' and (value::text)::int between 1 and 1000
    when 'login_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,4}$' and (value::text)::int between 1 and 1000
    when 'login_link_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,4}$' and (value::text)::int between 1 and 1000
    when 'unmet_search_daily_limit' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,5}$' and (value::text)::int between 1 and 10000
    when 'retention_rate_limit_days' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'retention_audit_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'rates_validity_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 36
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('login_daily_limit', '30', false,
   'Password sign-in attempts allowed per origin per UTC day (1-1000) / Intentos de ingreso con contraseña permitidos por origen y por día UTC (1-1000)'),
  ('login_link_daily_limit', '10', false,
   'E-mail links (first time / forgot password) allowed per origin per UTC day (1-1000) / Enlaces por mail (primera vez / olvidé mi contraseña) permitidos por origen y por día UTC (1-1000)'),
  ('unmet_search_daily_limit', '50', false,
   'Unmet-search records allowed per origin per UTC day (1-10000) / Registros de búsqueda sin resultado permitidos por origen y por día UTC (1-10000)');

-- ============================================================================
-- 2. rate_limit_hit: counts one action of one origin; true = allowed, false = limit reached
--    rate_limit_hit: cuenta una acción de un origen; true = permitida, false = límite alcanzado
-- ============================================================================
-- Only these three actions; the limit comes from the setting '<action>_daily_limit'. The reveal and report actions keep their
-- own functions. / Solo estas tres acciones; el límite sale del ajuste '<acción>_daily_limit'. Revelar y denunciar siguen con sus funciones.
create function public.rate_limit_hit(p_action text, p_origin_hash text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  today    date := (now() at time zone 'utc')::date;
  max_hits integer;
  counted  integer;
begin
  if p_action is null or p_action not in ('login', 'login_link', 'unmet_search') then
    raise exception 'unknown action' using errcode = '22023';
  end if;
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'origin hash must be 64 lower-case hex characters' using errcode = '22023';
  end if;
  select (a.value::text)::int into max_hits from public.app_settings a where a.key = p_action || '_daily_limit';
  if max_hits is null then
    raise exception 'the daily limit setting for this action is missing' using errcode = '23514';
  end if;

  insert into public.rate_limit_hits as h (action, origin_hash, day)
       values (p_action, p_origin_hash, today)
  on conflict (action, origin_hash, day)
    do update set hits = h.hits + 1 where h.hits < max_hits
  returning h.hits into counted;
  return counted is not null;
end
$$;
revoke execute on function public.rate_limit_hit(text, text) from public, anon, authenticated;
grant execute on function public.rate_limit_hit(text, text) to service_role;

-- ============================================================================
-- 3. Close the direct door and open the only one / Cerrar la puerta directa y abrir la única
-- ============================================================================
revoke execute on function public.log_search(integer, integer, text) from public, anon, authenticated, service_role;

-- Returns true when it recorded the search, false when the search has results OR the origin reached its limit (nothing recorded).
-- An invalid search fails with 22023 and is NOT counted (the whole call rolls back).
-- Devuelve true si registró la búsqueda, false si la búsqueda tiene resultados O el origen llegó a su límite (no se registra nada).
-- Una búsqueda inválida falla con 22023 y NO se cuenta (toda la llamada se deshace).
create function public.log_search_limited(p_therapy_id integer, p_location_id integer, p_service_mode text, p_origin_hash text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.rate_limit_hit('unmet_search', p_origin_hash) then
    return false;
  end if;
  return public.log_search(p_therapy_id, p_location_id, p_service_mode);
end
$$;
revoke execute on function public.log_search_limited(integer, integer, text, text) from public, anon, authenticated;
grant execute on function public.log_search_limited(integer, integer, text, text) to service_role;
