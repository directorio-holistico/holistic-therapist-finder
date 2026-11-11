-- Profile revisions, moderation events and restricted terms. SECURITY CHANGE: 3 tables, 5 functions, writes by the API.
-- Revisiones de perfil, eventos de moderación y términos restringidos. CAMBIO DE SEGURIDAD: 3 tablas, 5 funciones, escrituras por la API.
--
-- Business rules from the owner (11/11/2026) / Reglas de negocio del titular (11/11/2026):
--  * Restricted terms FLAG a revision, they never block it. The therapist can check a text in advance
--    (find_restricted_terms) and still send it knowing it will probably be rejected. The admin sees the
--    flagged terms in the queue.
--    Los términos restringidos MARCAN la revisión, nunca la bloquean. El terapeuta puede revisar un texto de
--    antemano (find_restricted_terms) y enviarlo igual, sabiendo que probablemente lo rechacen. El admin ve
--    los términos marcados en la cola.
--  * When a revision is rejected, the therapist receives the reason (rejection_reason).
--    Al rechazar una revisión, el terapeuta recibe el motivo (rejection_reason).
--
-- Who writes what / Quién escribe qué:
--  * profile_revisions: the therapist inserts and edits ONLY (profile_id, payload, suggested_therapy), and only
--    while the revision is a draft (column-level grants + RLS + guard trigger). Status changes (submit, approve,
--    reject, discard) will be server functions in the next commit. Nobody deletes revisions through the API.
--    profile_revisions: el terapeuta inserta y edita SOLO (profile_id, payload, suggested_therapy), y solo
--    mientras es borrador (permisos por columna + RLS + trigger). Los cambios de estado serán funciones de
--    servidor (commit siguiente). Nadie borra revisiones por la API.
--  * moderation_events: admin reads; nobody writes through the API (server functions write them).
--    moderation_events: lee el admin; nadie escribe por la API (las escriben funciones de servidor).
--  * restricted_terms: admin reads and writes (the four policies), so the admin panel can maintain the list.
--    restricted_terms: el admin lee y escribe (las cuatro políticas), así el panel puede mantener la lista.

-- ============================================================================
-- 1. Text normalization (lower case, no accents) / Normalización de texto (minúsculas, sin tildes)
-- ============================================================================
create function public.normalize_text(t text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select lower(translate(t,
    'áéíóúüñÁÉÍÓÚÜÑàèìòùâêîôû',
    'aeiouunAEIOUUNaeiouaeiou'))
$$;
revoke execute on function public.normalize_text(text) from public, anon, service_role;
grant execute on function public.normalize_text(text) to authenticated;

-- ============================================================================
-- 2. restricted_terms
-- ============================================================================
create table public.restricted_terms (
  id         integer generated always as identity primary key,
  term       text not null unique
             check (term = btrim(term) and char_length(term) between 2 and 80 and term = public.normalize_text(term)),
  is_active  boolean not null default true,
  note       text check (char_length(note) between 1 and 300),
  created_at timestamptz not null default now()
);
comment on table public.restricted_terms is
  'Words and phrases that flag a revision (never block it). Stored lower case, no accents; matched as whole words / Palabras que marcan una revisión (nunca la bloquean). Minúsculas y sin tildes; coincidencia por palabra completa.';

create function public.restricted_terms_normalize()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.term := btrim(public.normalize_text(new.term));
  return new;
end
$$;
create trigger restricted_terms_normalize
  before insert or update of term on public.restricted_terms
  for each row execute function public.restricted_terms_normalize();
revoke execute on function public.restricted_terms_normalize() from public, anon, authenticated, service_role;

-- STARTER LIST, PROVISIONAL: the owner validates and edits it. It lists cure claims, miracle claims,
-- guarantees, serious disease names and the words "treatment" and "diagnosis".
-- LISTA INICIAL, PROVISORIA: la valida y edita el titular. Incluye promesas de cura, de milagro, garantías,
-- nombres de enfermedades graves y las palabras "tratamiento" y "diagnóstico".
insert into public.restricted_terms (term, note) values
  ('cura', 'cure claim'), ('curas', 'cure claim'), ('curo', 'cure claim'), ('curar', 'cure claim'),
  ('curamos', 'cure claim'), ('curacion', 'cure claim'), ('curaciones', 'cure claim'),
  ('curativo', 'cure claim'), ('curativa', 'cure claim'),
  ('milagro', 'miracle claim'), ('milagros', 'miracle claim'), ('milagroso', 'miracle claim'), ('milagrosa', 'miracle claim'),
  ('garantizado', 'guarantee'), ('garantizada', 'guarantee'), ('garantizamos', 'guarantee'), ('100% efectivo', 'guarantee'),
  ('cancer', 'serious disease'), ('tumor', 'serious disease'), ('tumores', 'serious disease'),
  ('diabetes', 'serious disease'), ('sida', 'serious disease'), ('vih', 'serious disease'),
  ('alzheimer', 'serious disease'), ('esclerosis', 'serious disease'), ('covid', 'serious disease'),
  ('tratamiento', 'treatment claim'), ('diagnostico', 'diagnosis claim'), ('diagnosticar', 'diagnosis claim');

-- find_restricted_terms(text): which active terms appear in a text. SECURITY DEFINER because the therapist
-- cannot read the table; it only learns which terms appear in the text they typed. Needs a login, limits length.
-- find_restricted_terms(text): qué términos activos aparecen en un texto. SECURITY DEFINER porque el terapeuta
-- no puede leer la tabla; solo se entera de qué términos aparecen en lo que escribió. Exige sesión y limita el largo.
create function public.find_restricted_terms(p_text text)
returns text[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  norm text;
begin
  if auth.uid() is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_text is null then
    return '{}';
  end if;
  if char_length(p_text) > 5000 then
    raise exception 'text too long (max 5000 characters)' using errcode = '22023';
  end if;
  norm := public.normalize_text(p_text);
  return coalesce((
    select array_agg(t.term order by t.term)
    from public.restricted_terms t
    where t.is_active
      and norm ~ ('(^|[^a-z0-9])' || regexp_replace(t.term, '([^a-z0-9 ])', '\\\1', 'g') || '([^a-z0-9]|$)')
  ), '{}');
end
$$;
revoke execute on function public.find_restricted_terms(text) from public, anon, service_role;
grant execute on function public.find_restricted_terms(text) to authenticated;

-- ============================================================================
-- 3. profile_revisions
-- ============================================================================
create table public.profile_revisions (
  id                uuid primary key default gen_random_uuid(),
  profile_id        uuid     not null references public.therapist_profiles (id) on delete cascade,
  status_id         smallint not null references public.revision_statuses (id) on delete restrict,
  payload           jsonb    not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 20000),
  suggested_therapy text     check (suggested_therapy = btrim(suggested_therapy) and char_length(suggested_therapy) between 1 and 120),
  flagged_terms     text[]   not null default '{}',
  is_priority       boolean  not null default false,
  submitted_at      timestamptz,
  due_at            timestamptz,
  rejection_reason  text     check (char_length(rejection_reason) between 1 and 1000),
  decided_at        timestamptz,
  closed_at         timestamptz,
  created_at        timestamptz not null default now(),
  check (due_at is null or submitted_at is null or due_at >= submitted_at)
);
-- Only ONE open revision (draft or pending) per profile / Una sola revisión abierta por perfil
create unique index profile_revisions_one_open on public.profile_revisions (profile_id) where closed_at is null;
create index profile_revisions_status_idx on public.profile_revisions (status_id, due_at);
comment on table public.profile_revisions is
  'Proposed profile changes. The live profile never changes without an approved revision / Cambios propuestos al perfil. El perfil vigente no cambia sin una revisión aprobada.';

create function public.profile_revisions_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  status_code text;
begin
  if tg_op = 'INSERT' and new.status_id is null then
    select id into strict new.status_id from public.revision_statuses where code = 'draft';
  end if;

  -- 1) API roles may only change payload and suggested_therapy (checked first)
  -- 1) Los roles de la API solo cambian payload y suggested_therapy (se revisa primero)
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      if new.flagged_terms <> '{}' or new.is_priority or new.submitted_at is not null or new.due_at is not null
         or new.rejection_reason is not null or new.decided_at is not null or new.closed_at is not null
         or new.status_id <> (select id from public.revision_statuses where code = 'draft') then
        raise exception 'API roles can only create plain drafts' using errcode = '42501';
      end if;
    else
      if new.profile_id is distinct from old.profile_id
         or new.status_id is distinct from old.status_id
         or new.flagged_terms is distinct from old.flagged_terms
         or new.is_priority is distinct from old.is_priority
         or new.submitted_at is distinct from old.submitted_at
         or new.due_at is distinct from old.due_at
         or new.rejection_reason is distinct from old.rejection_reason
         or new.decided_at is distinct from old.decided_at
         or new.closed_at is distinct from old.closed_at then
        raise exception 'API roles cannot change revision workflow fields' using errcode = '42501';
      end if;
    end if;
  end if;

  -- 2) closed_at is set exactly when the status is final / closed_at existe exactamente cuando el estado es final
  select code into status_code from public.revision_statuses where id = new.status_id;
  if (status_code in ('approved', 'rejected', 'discarded')) <> (new.closed_at is not null) then
    raise exception 'closed_at must be set exactly when the revision is approved, rejected or discarded' using errcode = '23514';
  end if;
  -- 3) a rejection always carries its reason / un rechazo siempre lleva su motivo
  if status_code = 'rejected' and new.rejection_reason is null then
    raise exception 'a rejected revision needs a reason' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger profile_revisions_guard
  before insert or update on public.profile_revisions
  for each row execute function public.profile_revisions_guard();
revoke execute on function public.profile_revisions_guard() from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. moderation_events (append only; written by server functions)
-- ============================================================================
create table public.moderation_events (
  id                 bigint generated always as identity primary key,
  profile_id         uuid references public.therapist_profiles (id) on delete set null,
  revision_id        uuid references public.profile_revisions (id) on delete set null,
  actor_person_id    uuid references public.people (id) on delete set null,
  revision_status_id smallint references public.revision_statuses (id) on delete restrict,
  profile_status_id  smallint references public.profile_statuses (id) on delete restrict,
  reason             text check (char_length(reason) between 1 and 1000),
  created_at         timestamptz not null default now(),
  check (revision_status_id is not null or profile_status_id is not null)
);
create index moderation_events_profile_idx on public.moderation_events (profile_id, created_at desc);
comment on table public.moderation_events is
  'Who approved, rejected or suspended, when and why. The action is the status it moved to / Quién aprobó, rechazó o suspendió, cuándo y por qué. La acción es el estado al que pasó.';

-- ============================================================================
-- SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================

-- restricted_terms: the admin has the four policies; everyone else, nothing (no policy = no rows).
-- restricted_terms: el admin tiene las cuatro políticas; los demás, nada (sin política no hay filas).
alter table public.restricted_terms enable row level security;
grant select, insert, update, delete on public.restricted_terms to authenticated;
create policy restricted_terms_select_admin on public.restricted_terms
  for select to authenticated using ((select public.is_admin()));
create policy restricted_terms_insert_admin on public.restricted_terms
  for insert to authenticated with check ((select public.is_admin()));
create policy restricted_terms_update_admin on public.restricted_terms
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy restricted_terms_delete_admin on public.restricted_terms
  for delete to authenticated using ((select public.is_admin()));

-- profile_revisions: read own / admin; the therapist inserts and edits drafts of their own profile.
-- profile_revisions: lectura propia / admin; el terapeuta inserta y edita borradores de su propio perfil.
alter table public.profile_revisions enable row level security;
grant select on public.profile_revisions to authenticated;
grant insert (profile_id, payload, suggested_therapy) on public.profile_revisions to authenticated;
grant update (payload, suggested_therapy) on public.profile_revisions to authenticated;
create policy profile_revisions_select_own on public.profile_revisions
  for select to authenticated
  using (exists (select 1 from public.therapist_profiles tp
                 where tp.id = profile_id and tp.person_id = (select public.current_person_id())));
create policy profile_revisions_select_admin on public.profile_revisions
  for select to authenticated using ((select public.is_admin()));
create policy profile_revisions_insert_own on public.profile_revisions
  for insert to authenticated
  with check (exists (select 1 from public.therapist_profiles tp
                      where tp.id = profile_id and tp.person_id = (select public.current_person_id())));
create policy profile_revisions_update_own_draft on public.profile_revisions
  for update to authenticated
  using (exists (select 1 from public.therapist_profiles tp
                 where tp.id = profile_id and tp.person_id = (select public.current_person_id()))
         and status_id = (select id from public.revision_statuses where code = 'draft'))
  with check (exists (select 1 from public.therapist_profiles tp
                      where tp.id = profile_id and tp.person_id = (select public.current_person_id()))
              and status_id = (select id from public.revision_statuses where code = 'draft'));

-- moderation_events: admin reads; nobody writes through the API.
-- moderation_events: lee el admin; nadie escribe por la API.
alter table public.moderation_events enable row level security;
grant select on public.moderation_events to authenticated;
create policy moderation_events_select_admin on public.moderation_events
  for select to authenticated using ((select public.is_admin()));
