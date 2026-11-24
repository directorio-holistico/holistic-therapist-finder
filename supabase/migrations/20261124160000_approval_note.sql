-- SECURITY CHANGE / CAMBIO DE SEGURIDAD: 1 new column, approve_revision gets an OPTIONAL second argument, 1 new function (the owner deletes the note).
-- Nueva: 1 columna, approve_revision recibe un segundo argumento OPCIONAL, 1 función nueva (la persona elimina el mensaje).
--
-- The administrator may leave a short message when approving a revision (optional). The therapist reads it in "Mi perfil" and can delete it.
-- El administrador puede dejar un mensaje corto al aprobar una revisión (opcional). La terapeuta lo lee en "Mi perfil" y puede eliminarlo.
--
--  * profile_revisions.approval_note: 1..1000 characters, only on a DECIDED revision that was not rejected. No new table.
--    The owner can already read her own revisions (profile_revisions_select_own, SELECT on every column), so no new grant is needed.
--    She cannot WRITE it: the column is not in her INSERT / UPDATE column grants, and the revisions guard only lets definer code through.
--    Solo en una revisión DECIDIDA y no rechazada. Sin tabla nueva. La dueña ya lee sus revisiones (SELECT en todas las columnas),
--    no hace falta otro permiso. No puede ESCRIBIRLA: la columna no está en sus permisos de INSERT / UPDATE.
--  * approve_revision(uuid) becomes approve_revision(uuid, text default null): a function's arguments cannot change with CREATE OR REPLACE,
--    so the old one is dropped and recreated with the SAME body plus the note. Every call approve_revision(id) keeps working.
--    approve_revision(uuid) pasa a approve_revision(uuid, text default null): los argumentos no se cambian con CREATE OR REPLACE, así que se
--    borra la vieja y se crea de nuevo con el MISMO cuerpo más el mensaje. Toda llamada approve_revision(id) sigue funcionando.
--  * delete_my_approval_note(uuid): only the owner of the profile; it clears the note and nothing else. Errors: 42501 no session,
--    22023 null id, P0002 nothing to delete (also for someone else's revision, so it does not reveal that it exists).
--    Solo la dueña del perfil; borra el mensaje y nada más. Errores: 42501 sin sesión, 22023 id nulo, P0002 nada para borrar
--    (también si la revisión es ajena, para no revelar que existe).

alter table public.profile_revisions
  add column approval_note text
    check (approval_note = btrim(approval_note) and char_length(approval_note) between 1 and 1000);
alter table public.profile_revisions
  add constraint profile_revisions_note_only_when_decided
    check (approval_note is null or (decided_at is not null and rejection_reason is null));
comment on column public.profile_revisions.approval_note is
  'Optional message from the administrator when approving; the owner reads it and may delete it / Mensaje opcional del administrador al aprobar; la dueña lo lee y puede eliminarlo.';

drop function public.approve_revision(uuid);

create function public.approve_revision(p_revision_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor        uuid := public.current_person_id();
  rev          public.profile_revisions%rowtype;
  prof         public.therapist_profiles%rowtype;
  current_code text;
  profile_code text;
  published_id smallint;
  new_profile_status smallint;
  self_ok      boolean;
  note         text := nullif(btrim(p_note), '');
begin
  if actor is null or not public.is_admin() then
    raise exception 'administrator only' using errcode = '42501';
  end if;
  if note is not null and char_length(note) > 1000 then
    raise exception 'the message admits up to 1000 characters' using errcode = '22023';
  end if;

  select * into rev from public.profile_revisions where id = p_revision_id for update;
  if not found then
    raise exception 'revision not found' using errcode = 'P0002';
  end if;
  select code into strict current_code from public.revision_statuses where id = rev.status_id;
  if current_code <> 'pending_review' then
    raise exception 'only a pending revision can be approved' using errcode = '55000';
  end if;

  select * into prof from public.therapist_profiles where id = rev.profile_id for update;
  select code into strict profile_code from public.profile_statuses where id = prof.status_id;
  if profile_code in ('suspended', 'erased') then
    raise exception 'a % profile cannot be approved', profile_code using errcode = '55000';
  end if;

  select coalesce((value = 'true'::jsonb), false) into self_ok
    from public.app_settings where key = 'moderation_allow_self_approval';
  if prof.person_id = actor and not coalesce(self_ok, false) then
    raise exception 'you cannot approve a revision of your own profile' using errcode = '42501';
  end if;

  perform public.apply_revision_payload(prof.id, rev.payload);

  -- first approval of an unpublished profile publishes it / la primera aprobación de un perfil sin publicar lo publica
  if profile_code = 'unpublished' then
    select id into strict published_id from public.profile_statuses where code = 'published';
    new_profile_status := published_id;
  end if;
  update public.therapist_profiles
     set approved_at = coalesce(approved_at, now()),
         status_id = coalesce(new_profile_status, status_id)
   where id = prof.id;

  update public.profile_revisions
     set status_id = (select id from public.revision_statuses where code = 'approved'),
         decided_at = now(),
         closed_at = now(),
         approval_note = note
   where id = rev.id;

  insert into public.moderation_events (profile_id, revision_id, actor_person_id, revision_status_id, profile_status_id)
    values (prof.id, rev.id, actor, (select id from public.revision_statuses where code = 'approved'), new_profile_status);
end
$$;
revoke execute on function public.approve_revision(uuid, text) from public, anon, service_role;
grant execute on function public.approve_revision(uuid, text) to authenticated;

create function public.delete_my_approval_note(p_revision_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person uuid := public.current_person_id();
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_revision_id is null then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  update public.profile_revisions r
     set approval_note = null
   where r.id = p_revision_id
     and r.approval_note is not null
     and exists (select 1 from public.therapist_profiles tp where tp.id = r.profile_id and tp.person_id = person);
  if not found then
    raise exception 'nothing to delete' using errcode = 'P0002';
  end if;
end
$$;
revoke execute on function public.delete_my_approval_note(uuid) from public, anon, service_role;
grant execute on function public.delete_my_approval_note(uuid) to authenticated;
