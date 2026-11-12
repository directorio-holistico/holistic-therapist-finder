-- Reports and suspension. SECURITY CHANGE: 3 tables, 5 functions, 1 setting.
-- Denuncias y suspensión. CAMBIO DE SEGURIDAD: 3 tablas, 5 funciones, 1 ajuste.
--
--  * A report is created ONLY by the website server (role service_role) after the bot check and the origin limit decided
--    in ADR-0003. No API role (anon, authenticated) can create one, so the table cannot be flooded directly.
--    Una denuncia la crea SOLO el servidor de la web (rol service_role) tras la verificación de bots y el límite por origen
--    del ADR-0003. Ningún rol de la API (anon, authenticated) puede crearla: no se puede inundar la tabla directamente.
--  * Reporter email is optional (RN-11: no account, no email required). Details are optional free text, 1-1000 characters.
--    El mail del denunciante es opcional (RN-11: sin cuenta ni mail obligatorio). El detalle es texto libre opcional, 1-1000.
--  * Only the admin reads reports, closes them (dismissed / resolved, with a written note) and suspends or reinstates a
--    profile. Closing a report does not change the profile: suspending is a separate, explicit decision. Both leave a trace.
--    Solo el admin lee las denuncias, las cierra (descartada / resuelta, con nota escrita) y suspende o repone un perfil.
--    Cerrar una denuncia no cambia el perfil: suspender es una decisión aparte y explícita. Ambas dejan registro.
--  * Suspension is recorded in moderation_events (who, when, why) like the revision decisions of commit 16.
--    La suspensión queda en moderation_events (quién, cuándo, por qué) como las decisiones de revisión del commit 16.
--  * Retention: closed reports are deleted after retention_reports_months (12, PROPOSED, to be confirmed); open reports
--    are never purged. Retención: las denuncias cerradas se borran tras retention_reports_months (12, PROPUESTO, a confirmar);
--    las abiertas nunca se purgan.

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
    else true
  end);
insert into public.app_settings (key, value, is_public, description) values
  ('retention_reports_months', '12', false,
   'Months to keep CLOSED reports (1-120); open reports are never purged / Meses que se conservan las denuncias CERRADAS (1-120); las abiertas nunca se purgan');

-- ============================================================================
-- 2. Catalogs (tables, not fixed lists) / Catálogos (tablas, no listas fijas)
-- ============================================================================
create table public.report_reasons (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.report_reasons is 'Why a profile is reported / Por qué se denuncia un perfil.';
create table public.report_statuses (
  id         smallint generated always as identity primary key,
  code       text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);
comment on table public.report_statuses is 'Life cycle of a report: open, dismissed, resolved / Ciclo de una denuncia: abierta, descartada, resuelta.';
insert into public.report_reasons (code, sort_order) values
  ('cure_claim', 1), ('false_information', 2), ('inappropriate_content', 3), ('impersonation', 4), ('unsafe_practice', 5), ('other', 6);
insert into public.report_statuses (code, sort_order) values ('open', 1), ('dismissed', 2), ('resolved', 3);

-- ============================================================================
-- 3. reports
-- ============================================================================
create table public.reports (
  id                  bigint generated always as identity primary key,
  profile_id          uuid references public.therapist_profiles (id) on delete set null,
  reason_id           smallint not null references public.report_reasons (id) on delete restrict,
  details             text check (details = btrim(details) and char_length(details) between 1 and 1000),
  reporter_email      text check (reporter_email = lower(btrim(reporter_email)) and char_length(reporter_email) <= 254
                                  and reporter_email ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
  status_id           smallint not null references public.report_statuses (id) on delete restrict,
  created_at          timestamptz not null default now(),
  resolved_at         timestamptz,
  resolved_by_person_id uuid references public.people (id) on delete set null,
  resolution_note     text check (resolution_note = btrim(resolution_note) and char_length(resolution_note) between 1 and 1000),
  check ((resolved_at is null) = (resolution_note is null))
);
create index reports_status_created_idx on public.reports (status_id, created_at);
create index reports_profile_idx on public.reports (profile_id);
comment on table public.reports is
  'Reports of profiles. Created by the server only; read and closed by the admin / Denuncias de perfiles. Las crea solo el servidor; las lee y cierra el admin.';

-- SECURITY: RLS + GRANT. Catalogs: authenticated read. reports: admin read; nobody writes through the API.
-- SEGURIDAD: RLS + GRANT. Catálogos: lectura authenticated. reports: lee el admin; nadie escribe por la API.
alter table public.report_reasons enable row level security;
alter table public.report_statuses enable row level security;
grant select on public.report_reasons, public.report_statuses to authenticated;
create policy report_reasons_select_authenticated on public.report_reasons for select to authenticated using (true);
create policy report_statuses_select_authenticated on public.report_statuses for select to authenticated using (true);
alter table public.reports enable row level security;
grant select on public.reports to authenticated;
create policy reports_select_admin on public.reports
  for select to authenticated using ((select public.is_admin()));

-- ============================================================================
-- 4. report_profile (server only) / report_profile (solo servidor)
-- ============================================================================
create function public.report_profile(
  p_profile_id     uuid,
  p_reason_code    text,
  p_details        text default null,
  p_reporter_email text default null)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reason_id smallint;
  details   text := nullif(btrim(p_details), '');
  email     text := nullif(lower(btrim(p_reporter_email)), '');
  new_id    bigint;
begin
  -- the same message for an unknown, hidden or null profile: the answer never tells them apart
  -- el mismo mensaje para un perfil inexistente, oculto o nulo: la respuesta nunca los distingue
  if p_profile_id is null or not public.is_published_profile(p_profile_id) then
    raise exception 'unknown profile' using errcode = '22023';
  end if;
  select r.id into reason_id from public.report_reasons r where r.code = p_reason_code and r.is_active;
  if reason_id is null then
    raise exception 'unknown reason' using errcode = '22023';
  end if;
  if details is not null and char_length(details) > 1000 then
    raise exception 'details are too long (1-1000 characters)' using errcode = '22023';
  end if;
  if email is not null and (char_length(email) > 254 or email !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$') then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  insert into public.reports (profile_id, reason_id, details, reporter_email, status_id)
    values (p_profile_id, reason_id, details, email, (select s.id from public.report_statuses s where s.code = 'open'))
    returning id into new_id;
  return new_id;
end
$$;
revoke execute on function public.report_profile(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.report_profile(uuid, text, text, text) to service_role;

-- ============================================================================
-- 5. Admin functions / Funciones del admin
-- ============================================================================
create function public.close_report(p_report_id bigint, p_status_code text, p_note text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor   uuid := public.current_person_id();
  note    text := btrim(p_note);
  rep     public.reports;
  current_code text;
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if p_status_code is null or p_status_code not in ('dismissed', 'resolved') then
    raise exception 'a report is closed as dismissed or resolved' using errcode = '22023';
  end if;
  if note is null or char_length(note) not between 1 and 1000 then
    raise exception 'closing a report needs a note (1-1000 characters)' using errcode = '22023';
  end if;
  select * into rep from public.reports where id = p_report_id for update;
  if not found then
    raise exception 'report not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.report_statuses where id = rep.status_id;
  if current_code <> 'open' then
    raise exception 'only an open report can be closed' using errcode = '55000';
  end if;
  update public.reports
     set status_id = (select id from public.report_statuses where code = p_status_code),
         resolved_at = now(), resolved_by_person_id = actor, resolution_note = note
   where id = rep.id;
end
$$;
revoke execute on function public.close_report(bigint, text, text) from public, anon, service_role;
grant execute on function public.close_report(bigint, text, text) to authenticated;

create function public.suspend_profile(p_profile_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor  uuid := public.current_person_id();
  reason text := btrim(p_reason);
  prof   public.therapist_profiles;
  current_code text;
  suspended_id smallint := (select id from public.profile_statuses where code = 'suspended');
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if reason is null or char_length(reason) not between 1 and 500 then
    raise exception 'a suspension needs a reason (1-500 characters)' using errcode = '22023';
  end if;
  select * into prof from public.therapist_profiles where id = p_profile_id for update;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.profile_statuses where id = prof.status_id;
  if current_code in ('suspended', 'erased') then
    raise exception 'a % profile cannot be suspended', current_code using errcode = '55000';
  end if;
  update public.therapist_profiles set status_id = suspended_id, status_reason = reason where id = prof.id;
  insert into public.moderation_events (profile_id, actor_person_id, profile_status_id, reason)
    values (prof.id, actor, suspended_id, reason);
end
$$;
revoke execute on function public.suspend_profile(uuid, text) from public, anon, service_role;
grant execute on function public.suspend_profile(uuid, text) to authenticated;

-- A suspended profile goes back to published if it had been approved before, otherwise to unpublished.
-- Un perfil suspendido vuelve a publicado si ya había sido aprobado, si no a no publicado.
create function public.reinstate_profile(p_profile_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor  uuid := public.current_person_id();
  reason text := btrim(p_reason);
  prof   public.therapist_profiles;
  current_code text;
  target_id smallint;
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if reason is null or char_length(reason) not between 1 and 1000 then
    raise exception 'reinstating needs a reason (1-1000 characters)' using errcode = '22023';
  end if;
  select * into prof from public.therapist_profiles where id = p_profile_id for update;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.profile_statuses where id = prof.status_id;
  if current_code <> 'suspended' then
    raise exception 'only a suspended profile can be reinstated' using errcode = '55000';
  end if;
  select id into strict target_id from public.profile_statuses
    where code = case when prof.approved_at is null then 'unpublished' else 'published' end;
  update public.therapist_profiles set status_id = target_id, status_reason = null where id = prof.id;
  insert into public.moderation_events (profile_id, actor_person_id, profile_status_id, reason)
    values (prof.id, actor, target_id, reason);
end
$$;
revoke execute on function public.reinstate_profile(uuid, text) from public, anon, service_role;
grant execute on function public.reinstate_profile(uuid, text) to authenticated;

-- ============================================================================
-- 6. Retention / Retención
-- ============================================================================
create function public.purge_expired_reports()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  months  integer;
  removed integer;
begin
  select (value::text)::int into months from public.app_settings where key = 'retention_reports_months';
  if months is null then
    raise exception 'setting retention_reports_months is missing' using errcode = '23514';
  end if;
  delete from public.reports
   where status_id <> (select id from public.report_statuses where code = 'open')
     and resolved_at < now() - make_interval(months => months);
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.purge_expired_reports() from public, anon, authenticated;
grant execute on function public.purge_expired_reports() to service_role;
