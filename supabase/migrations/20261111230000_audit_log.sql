-- Audit log. SECURITY CHANGE: 1 table, 3 functions, 6 audit triggers + 2 protection triggers, 1 setting.
-- Registro de auditoría. CAMBIO DE SEGURIDAD: 1 tabla, 3 funciones, 6 triggers de auditoría + 2 de protección, 1 ajuste.
--
--  * WHO changed WHAT and WHEN on the tables that hold identity, privileges or live content: people, person_roles,
--    therapist_profiles, profile_contacts, app_settings, restricted_terms. One row per change, written by a trigger
--    AFTER the change, in the same transaction (if the change rolls back, so does its record).
--    QUIÉN cambió QUÉ y CUÁNDO en las tablas con identidad, privilegios o contenido vigente: people, person_roles,
--    therapist_profiles, profile_contacts, app_settings, restricted_terms. Una fila por cambio, escrita por un trigger
--    DESPUÉS del cambio, en la misma transacción (si el cambio se revierte, su registro también).
--  * NO personal value is ever stored: for an update it keeps only the NAMES of the columns that changed; the row is
--    identified by its key (ids). That is why erasing a person leaves nothing personal in this table.
--    Nunca se guarda un valor personal: en una actualización solo guarda los NOMBRES de las columnas que cambiaron; la
--    fila se identifica por su clave (ids). Por eso eliminar a una persona no deja nada personal en esta tabla.
--    Only exception: app_settings keeps old and new VALUE (numbers and booleans, nothing personal), because "someone
--    changed reveal_daily_limit" is useless without the values. / Única excepción: app_settings guarda el valor viejo y
--    el nuevo (números y booleanos, nada personal), porque "alguien cambió reveal_daily_limit" no sirve sin los valores.
--  * Who: actor_person_id (from the login, null when there is none) and actor_role (the role of the request: authenticated,
--    service_role... null for migrations and manual work as owner). No IP, no user agent.
--    Quién: actor_person_id (del login, nulo si no hay) y actor_role (el rol del pedido: authenticated, service_role...
--    nulo en migraciones y trabajo manual como dueño). Sin IP ni user agent.
--  * Append-only: only the admin reads; nobody writes through the API; a trigger refuses UPDATE, DELETE and TRUNCATE
--    (the retention purge is the only way to delete, and only through its own function).
--    Solo se agrega: solo el admin lee; nadie escribe por la API; un trigger rechaza UPDATE, DELETE y TRUNCATE (la
--    purga por retención es la única forma de borrar, y solo por su función).
--  * No foreign key to people on purpose: an FK with ON DELETE SET NULL would try to UPDATE this table.
--    Sin clave foránea a people a propósito: un FK con ON DELETE SET NULL intentaría hacer UPDATE en esta tabla.
--  * Retention: retention_audit_months = 24 (PROPOSED, to be confirmed by the owner; configurable 1-120).
--    Retención: retention_audit_months = 24 (PROPUESTO, a confirmar por el dueño; configurable 1-120).

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
    when 'retention_rate_limit_days' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,2}$' and (value::text)::int between 1 and 30
    when 'retention_audit_months' then jsonb_typeof(value) = 'number' and value::text ~ '^[0-9]{1,3}$' and (value::text)::int between 1 and 120
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('retention_audit_months', '24', false,
   'Months to keep the audit log (1-120) / Meses que se conserva el registro de auditoría (1-120)');

-- ============================================================================
-- 2. audit_log
-- ============================================================================
create table public.audit_log (
  id               bigint generated always as identity primary key,
  occurred_at      timestamptz not null default now(),
  table_name       text not null check (table_name ~ '^[a-z][a-z0-9_]{0,62}$'),
  operation        text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  row_key          text not null check (char_length(row_key) between 1 and 200),
  changed_fields   text[],
  detail           jsonb,
  actor_person_id  uuid,
  actor_role       text check (actor_role ~ '^[a-z_]{1,30}$'),
  -- an UPDATE always names at least one changed column; INSERT and DELETE never do
  -- un UPDATE siempre nombra al menos una columna cambiada; INSERT y DELETE nunca
  check ((operation = 'UPDATE') = (coalesce(cardinality(changed_fields), 0) > 0)),
  -- values are kept only for app_settings (see the header) / los valores solo se guardan en app_settings
  check (detail is null or table_name = 'app_settings')
);
create index audit_log_occurred_idx on public.audit_log (occurred_at);
create index audit_log_row_idx on public.audit_log (table_name, row_key);
comment on table public.audit_log is
  'Append-only record of who changed what. Column NAMES only, never personal values. / Registro solo-agregar de quién cambió qué. Solo NOMBRES de columnas, nunca valores personales.';

-- SECURITY: RLS + GRANT. Only the admin reads; nobody writes through the API.
-- SEGURIDAD: RLS + GRANT. Solo el admin lee; nadie escribe por la API.
alter table public.audit_log enable row level security;
grant select on public.audit_log to authenticated;
create policy audit_log_select_admin on public.audit_log
  for select to authenticated using ((select public.is_admin()));

-- ============================================================================
-- 3. The trigger function that writes the record / La función de trigger que escribe el registro
-- ============================================================================
create function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  old_j   jsonb;
  new_j   jsonb;
  row_j   jsonb;
  changed text[];
  key_txt text;
  det     jsonb := null;
  claims  jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
begin
  if tg_op = 'INSERT' then
    row_j := to_jsonb(new);
  elsif tg_op = 'DELETE' then
    row_j := to_jsonb(old);
  else
    old_j := to_jsonb(old);
    new_j := to_jsonb(new);
    row_j := new_j;
    select array_agg(n.key order by n.key) into changed
      from jsonb_each(new_j) n where old_j -> n.key is distinct from n.value;
    if changed is null then
      return null;   -- nothing really changed: no record / no cambió nada: sin registro
    end if;
  end if;

  -- The key columns come from the trigger arguments (ids only, never personal data).
  -- Las columnas de la clave vienen de los argumentos del trigger (solo ids, nunca datos personales).
  select string_agg(row_j ->> c.col, ':' order by c.ord) into key_txt
    from unnest(tg_argv) with ordinality as c(col, ord);

  if tg_table_name = 'app_settings' then
    det := jsonb_build_object('old', old_j -> 'value', 'new', new_j -> 'value');
    if tg_op = 'INSERT' then det := jsonb_build_object('new', row_j -> 'value');
    elsif tg_op = 'DELETE' then det := jsonb_build_object('old', row_j -> 'value');
    end if;
  end if;

  insert into public.audit_log (table_name, operation, row_key, changed_fields, detail, actor_person_id, actor_role)
  values (tg_table_name, tg_op, key_txt, changed, det, public.current_person_id(), claims ->> 'role');
  return null;
end
$$;
revoke execute on function public.audit_row_change() from public, anon, authenticated, service_role;

create trigger audit_people             after insert or update or delete on public.people             for each row execute function public.audit_row_change('id');
create trigger audit_person_roles       after insert or update or delete on public.person_roles       for each row execute function public.audit_row_change('person_id', 'role_id');
create trigger audit_therapist_profiles after insert or update or delete on public.therapist_profiles for each row execute function public.audit_row_change('id');
create trigger audit_profile_contacts   after insert or update or delete on public.profile_contacts   for each row execute function public.audit_row_change('profile_id', 'contact_type_id');
create trigger audit_app_settings       after insert or update or delete on public.app_settings       for each row execute function public.audit_row_change('key');
create trigger audit_restricted_terms   after insert or update or delete on public.restricted_terms   for each row execute function public.audit_row_change('id');

-- ============================================================================
-- 4. Append-only protection / Protección solo-agregar
-- ============================================================================
create function public.audit_log_protect()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- The purge function sets this flag for its own transaction only. / La función de purga activa esta marca solo en su transacción.
  if tg_op = 'DELETE' and current_setting('app.audit_purge', true) = 'on' then
    return old;
  end if;
  raise exception 'audit_log is append-only' using errcode = '42501';
end
$$;
revoke execute on function public.audit_log_protect() from public, anon, authenticated, service_role;

create trigger audit_log_no_change before update or delete on public.audit_log
  for each row execute function public.audit_log_protect();
create trigger audit_log_no_truncate before truncate on public.audit_log
  for each statement execute function public.audit_log_protect();

-- ============================================================================
-- 5. Purge / Purga
-- ============================================================================
create function public.purge_expired_audit_log()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  months  integer;
  removed integer;
begin
  select (value::text)::int into months from public.app_settings where key = 'retention_audit_months';
  if months is null then
    raise exception 'setting retention_audit_months is missing' using errcode = '23514';
  end if;
  perform set_config('app.audit_purge', 'on', true);
  delete from public.audit_log where occurred_at < now() - make_interval(months => months);
  get diagnostics removed = row_count;
  perform set_config('app.audit_purge', 'off', true);
  return removed;
end
$$;
revoke execute on function public.purge_expired_audit_log() from public, anon, authenticated;
grant execute on function public.purge_expired_audit_log() to service_role;
