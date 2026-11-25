-- SECURITY CHANGE / CAMBIO DE SEGURIDAD: replaces approve_revision(uuid, text) (same signature, same permissions) and swaps one CHECK constraint.
-- Reemplaza approve_revision(uuid, text) (misma firma, mismos permisos) y cambia una restricción CHECK.
--
-- The approval message limit goes from 1000 to 2000 characters (a real message with spelling corrections did not fit).
-- El tope del mensaje de aprobación pasa de 1000 a 2000 caracteres (un mensaje real con correcciones de ortografía no entraba).
--
--  * The column check created by 20261124160000 has an automatic name, so it is found by its definition and replaced by a named one.
--    La restricción de la columna creada por 20261124160000 tiene nombre automático: se la busca por su definición y se la reemplaza por una con nombre.
--  * approve_revision(uuid, text): CREATE OR REPLACE keeps the grants; they are repeated anyway. The body is the same except the limit.
--    CREATE OR REPLACE conserva los permisos; igual se repiten. El cuerpo es el mismo salvo el tope.
--  * delete_my_approval_note is not touched. / delete_my_approval_note no se toca.

do $$
declare
  old_check text;
begin
  select c.conname into old_check
    from pg_constraint c
   where c.conrelid = 'public.profile_revisions'::regclass
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) like '%char_length(approval_note)%';
  if old_check is null then
    raise exception 'the length check of approval_note was not found' using errcode = 'P0002';
  end if;
  execute format('alter table public.profile_revisions drop constraint %I', old_check);
end
$$;

alter table public.profile_revisions
  add constraint profile_revisions_note_length
    check (approval_note = btrim(approval_note) and char_length(approval_note) between 1 and 2000);

create or replace function public.approve_revision(p_revision_id uuid, p_note text default null)
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
  if note is not null and char_length(note) > 2000 then
    raise exception 'the message admits up to 2000 characters' using errcode = '22023';
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
