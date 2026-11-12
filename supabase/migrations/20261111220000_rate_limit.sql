-- Rate limit by origin for the contact reveal (ADR-0003). SECURITY CHANGE: 1 table, 2 functions, 2 settings,
-- and the direct door `reveal_contact` is CLOSED for visitors.
-- Límite de pedidos por origen para el revelado de contacto (ADR-0003). CAMBIO DE SEGURIDAD: 1 tabla, 2 funciones,
-- 2 ajustes, y la puerta directa `reveal_contact` queda CERRADA para los visitantes.
--
--  * Before: `anon` (a public key, shipped in the browser) could call reveal_contact profile by profile and harvest every
--    phone. After: NO API role runs reveal_contact. The only door is reveal_contact_limited(profile, origin_hash), executable
--    only by the website server (service_role), which first reads the visitor's address, checks Cloudflare Turnstile and
--    computes the origin hash (HMAC-SHA256 with a secret key that never reaches the database).
--    Antes: `anon` (una clave pública, que viaja en el navegador) podía llamar reveal_contact perfil por perfil y juntar
--    todos los teléfonos. Ahora: NINGÚN rol de la API ejecuta reveal_contact. La única puerta es
--    reveal_contact_limited(perfil, hash_origen), que ejecuta solo el servidor de la web (service_role): él lee la dirección
--    del visitante, verifica Cloudflare Turnstile y calcula el hash del origen (HMAC-SHA256 con una clave secreta que nunca
--    llega a la base).
--  * The database never sees an address: only 64 hex characters. Count and reveal happen in ONE transaction, and the count
--    is one atomic statement (INSERT ... ON CONFLICT DO UPDATE ... WHERE hits < limit), so two simultaneous calls cannot
--    both pass the last slot.
--    La base nunca ve una dirección: solo 64 caracteres hexadecimales. Contar y revelar ocurren en UNA transacción, y el
--    conteo es una sola sentencia atómica, así que dos llamadas simultáneas no pasan las dos por el último lugar.
--  * Every valid call counts, even for a hidden or unknown profile: otherwise guessing ids would be free.
--    Toda llamada válida cuenta, incluso para un perfil oculto o inexistente: si no, adivinar ids saldría gratis.
--  * Over the limit: error with its own SQLSTATE 'RL429' and nothing is revealed or counted.
--    Pasado el límite: error con SQLSTATE propio 'RL429', y no se revela ni se cuenta nada.
--  * Day window = fixed UTC day (up to 2x the limit can pass around midnight; accepted in ADR-0003).
--    Ventana = día UTC fijo (cerca de la medianoche pueden pasar hasta 2 veces el límite; aceptado en el ADR-0003).

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
    when 'retention_rate_limit_days' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('reveal_daily_limit', '20', false,
   'Contact reveals allowed per origin per UTC day (1-10000) / Revelados de contacto permitidos por origen y por día UTC (1-10000)'),
  ('retention_rate_limit_days', '2', false,
   'Days to keep the rate-limit counters (1-30) / Días que se conservan los contadores del límite de pedidos (1-30)');

-- ============================================================================
-- 2. rate_limit_hits: one row per action, origin hash and UTC day
-- ============================================================================
create table public.rate_limit_hits (
  id           bigint generated always as identity primary key,
  action       text    not null check (action ~ '^[a-z][a-z0-9_]{0,29}$'),
  origin_hash  text    not null check (origin_hash ~ '^[0-9a-f]{64}$'),
  day          date    not null,
  hits         integer not null default 1 check (hits between 1 and 1000000),
  unique (action, origin_hash, day)
);
create index rate_limit_hits_day_idx on public.rate_limit_hits (day);
comment on table public.rate_limit_hits is
  'Daily counters per action and keyed origin hash (HMAC, never the address). Kept 2 days. Server only. / Contadores diarios por acción y hash con clave del origen (HMAC, nunca la dirección). Se conservan 2 días. Solo servidor.';

-- SECURITY: RLS on, NO grants and NO policies: no API role reads or writes it, not even the admin (hashes are
-- pseudonymous data with no use for a person). Only the SECURITY DEFINER functions below touch it.
-- SEGURIDAD: RLS activado, SIN permisos y SIN políticas: ningún rol de la API la lee ni la escribe, ni siquiera el admin
-- (son datos seudónimos sin utilidad para una persona). Solo la tocan las funciones SECURITY DEFINER de abajo.
alter table public.rate_limit_hits enable row level security;

-- ============================================================================
-- 3. Close the direct door / Cerrar la puerta directa
-- ============================================================================
revoke execute on function public.reveal_contact(uuid) from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. The only door: count and reveal in one transaction / La única puerta: contar y revelar en una transacción
-- ============================================================================
create function public.reveal_contact_limited(p_profile_id uuid, p_origin_hash text)
returns table (contact_type text, value text, accepts_whatsapp boolean)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  today   date := (now() at time zone 'utc')::date;
  max_hits integer;
  counted integer;
begin
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'origin hash must be 64 lower-case hex characters' using errcode = '22023';
  end if;
  select (a.value::text)::int into max_hits from public.app_settings a where a.key = 'reveal_daily_limit';
  if max_hits is null then
    raise exception 'setting reveal_daily_limit is missing' using errcode = '23514';
  end if;

  -- One atomic statement: it increments only while below the limit; at the limit it returns no row.
  -- Una sola sentencia atómica: suma solo mientras está bajo el límite; en el límite no devuelve fila.
  insert into public.rate_limit_hits as h (action, origin_hash, day)
       values ('reveal', p_origin_hash, today)
  on conflict (action, origin_hash, day)
    do update set hits = h.hits + 1 where h.hits < max_hits
  returning h.hits into counted;
  if counted is null then
    raise exception 'rate limit reached' using errcode = 'RL429';
  end if;

  return query select r.contact_type, r.value, r.accepts_whatsapp from public.reveal_contact(p_profile_id) r;
end
$$;
revoke execute on function public.reveal_contact_limited(uuid, text) from public, anon, authenticated;
grant execute on function public.reveal_contact_limited(uuid, text) to service_role;

-- ============================================================================
-- 5. Purge / Purga
-- ============================================================================
create function public.purge_expired_rate_limit_hits()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  keep_days integer;
  removed   integer;
begin
  select (value::text)::int into keep_days from public.app_settings where key = 'retention_rate_limit_days';
  if keep_days is null then
    raise exception 'setting retention_rate_limit_days is missing' using errcode = '23514';
  end if;
  delete from public.rate_limit_hits
    where day < (now() at time zone 'utc')::date - keep_days;
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.purge_expired_rate_limit_hits() from public, anon, authenticated;
grant execute on function public.purge_expired_rate_limit_hits() to service_role;
