-- Report a profile behind the origin limit (ADR-0003). SECURITY CHANGE: 1 function, 1 setting, 1 permission removed.
-- Denunciar un perfil detrás del límite por origen (ADR-0003). CAMBIO DE SEGURIDAD: 1 función, 1 ajuste, 1 permiso quitado.
--
--  * Until now report_profile(...) was open to service_role with NO count: the website server could create reports without
--    limit. Now the only door is report_profile_limited(...), which counts the origin and creates the report in ONE transaction,
--    like reveal_contact_limited (commit 24). report_profile stays as an internal step: no API role can call it.
--    Hasta ahora report_profile(...) estaba abierta a service_role SIN contar: el servidor podía crear denuncias sin límite.
--    Ahora la única puerta es report_profile_limited(...), que cuenta el origen y crea la denuncia en UNA transacción, como
--    reveal_contact_limited (commit 24). report_profile queda como paso interno: ningún rol de la API puede llamarla.
--  * Same counter table (rate_limit_hits) with its own action 'report': reports and reveals never use each other's slots.
--    Misma tabla de contadores (rate_limit_hits) con su propia acción 'report': denuncias y revelados no se gastan lugares.
--  * An invalid report (unknown profile, bad reason, bad email) fails inside the same transaction, so it is NOT counted.
--    Una denuncia inválida (perfil inexistente, motivo o mail inválido) falla en la misma transacción, así que NO se cuenta.
--  * The limit is a setting: report_daily_limit = 5 per origin per UTC day (PROPOSED, to be confirmed).
--    El límite es un ajuste: report_daily_limit = 5 por origen y por día UTC (PROPUESTO, a confirmar).

-- ============================================================================
-- 1. Setting / Ajuste
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
    when 'retention_rate_limit_days' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'retention_audit_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    when 'rates_validity_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 36
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('report_daily_limit', '5', false,
   'Reports allowed per origin per UTC day (1-1000) / Denuncias permitidas por origen y por día UTC (1-1000)');

-- ============================================================================
-- 2. The only door: count and report in one transaction / La única puerta: contar y denunciar en una transacción
-- ============================================================================
create function public.report_profile_limited(
  p_profile_id     uuid,
  p_reason_code    text,
  p_details        text,
  p_reporter_email text,
  p_origin_hash    text)
returns bigint
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
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'origin hash must be 64 lower-case hex characters' using errcode = '22023';
  end if;
  select (a.value::text)::int into max_hits from public.app_settings a where a.key = 'report_daily_limit';
  if max_hits is null then
    raise exception 'setting report_daily_limit is missing' using errcode = '23514';
  end if;

  -- One atomic statement: it increments only while below the limit; at the limit it returns no row.
  -- Una sola sentencia atómica: suma solo mientras está bajo el límite; en el límite no devuelve fila.
  insert into public.rate_limit_hits as h (action, origin_hash, day)
       values ('report', p_origin_hash, today)
  on conflict (action, origin_hash, day)
    do update set hits = h.hits + 1 where h.hits < max_hits
  returning h.hits into counted;
  if counted is null then
    raise exception 'rate limit reached' using errcode = 'RL429';
  end if;

  -- If the report is invalid this raises and the transaction undoes the count above.
  -- Si la denuncia es inválida esto falla y la transacción deshace el conteo de arriba.
  return public.report_profile(p_profile_id, p_reason_code, p_details, p_reporter_email);
end
$$;
revoke execute on function public.report_profile_limited(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.report_profile_limited(uuid, text, text, text, text) to service_role;

-- ============================================================================
-- 3. Close the direct door / Cerrar la puerta directa
-- ============================================================================
revoke execute on function public.report_profile(uuid, text, text, text) from public, anon, authenticated, service_role;
