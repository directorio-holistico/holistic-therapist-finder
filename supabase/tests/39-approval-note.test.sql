-- The optional message when approving: who can leave it, who reads it, who deletes it, and what the database refuses.
-- El mensaje opcional al aprobar: quién lo deja, quién lo lee, quién lo elimina y qué rechaza la base.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000039' || k)::uuid, k || '@example.test', now() from unnest(array['a1','b2','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000039' || k)::uuid, ('00000000-0000-0000-0000-0000000039' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','b2','ad']) k;
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000039ad'::uuid, id from public.roles where code = 'admin';
insert into public.therapist_profiles (id, person_id, status_id, approved_at, location_id, headline)
  select ('20000000-0000-0000-0000-0000000039' || k)::uuid, ('10000000-0000-0000-0000-0000000039' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished'), now() - interval '30 days',
         (select l.id from public.locations l join public.location_levels ll on ll.id = l.level_id where ll.code = 'city' order by l.id limit 1),
         'Original ' || k
  from unnest(array['a1','b2']) k;
insert into public.profile_contacts (profile_id, contact_type_id, value)
  select ('20000000-0000-0000-0000-0000000039' || k)::uuid, (select id from public.contact_types where code = 'email'), k || '@example.test'
  from unnest(array['a1','b2']) k;
update public.therapist_profiles set status_id = (select id from public.profile_statuses where code = 'published')
  where id in ('20000000-0000-0000-0000-0000000039a1', '20000000-0000-0000-0000-0000000039b2');

-- helper: open a pending revision (owner) / ayuda: abrir una revisión pendiente (dueño)
create function pg_temp.open_revision(p_id uuid, p_profile text, p_payload jsonb)
returns void language sql as $$
  insert into public.profile_revisions (id, profile_id, status_id, payload, submitted_at, due_at)
  values (p_id, ('20000000-0000-0000-0000-0000000039' || p_profile)::uuid,
          (select id from public.revision_statuses where code = 'pending_review'), p_payload, now(), now() + interval '3 days');
$$;
select pg_temp.open_revision('30000000-0000-0000-0000-0000000039a1', 'a1', '{"headline":"Nuevo a1"}'::jsonb);
select pg_temp.open_revision('30000000-0000-0000-0000-0000000039b2', 'b2', '{"headline":"Nuevo b2"}'::jsonb);

-- 1) ANON: neither function / ANON: ninguna de las dos funciones
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000039a1', 'x'); raise exception 'anon must not approve';
  exception when insufficient_privilege then null; end;
  begin perform public.delete_my_approval_note('30000000-0000-0000-0000-0000000039a1'); raise exception 'anon must not delete a note';
  exception when insufficient_privilege then null; end;
end
$$;
reset role;
reset session authorization;

-- 2) a1 (therapist, not an administrator) cannot approve, even with a message / a1 (terapeuta) no puede aprobar
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039a1","role":"authenticated"}', true);
do $$
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000039b2', 'x'); raise exception 'a non-admin must not approve';
  exception when sqlstate '42501' then null; end;
end
$$;
reset role;
reset session authorization;

-- 3) ad (administrator): a message over 1000 characters is refused and nothing changes; a blank one counts as no message
-- 3) ad (admin): un mensaje de más de 1000 caracteres se rechaza y no cambia nada; uno en blanco cuenta como sin mensaje
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039ad","role":"authenticated"}', true);
do $$
begin
  begin perform public.approve_revision('30000000-0000-0000-0000-0000000039b2', repeat('x', 1001)); raise exception 'a 1001-character message must be refused';
  exception when sqlstate '22023' then null; end;
end
$$;
reset role;
reset session authorization;
do $$
begin
  if (select code from public.revision_statuses where id = (select status_id from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039b2')) <> 'pending_review' then
    raise exception 'a refused message must leave the revision pending';
  end if;
end
$$;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039ad","role":"authenticated"}', true);
select public.approve_revision('30000000-0000-0000-0000-0000000039b2', '   ');
-- a1: approved WITH a message (trimmed) / a1: aprobada CON mensaje (recortado)
select public.approve_revision('30000000-0000-0000-0000-0000000039a1', '  Hola, aprobé tu perfil.  ');
reset role;
reset session authorization;

do $$
begin
  if (select approval_note from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039b2') is not null then
    raise exception 'a blank message must be stored as no message';
  end if;
  if (select approval_note from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039a1') is distinct from 'Hola, aprobé tu perfil.' then
    raise exception 'the message must be stored trimmed';
  end if;
  if (select headline from public.therapist_profiles where id = '20000000-0000-0000-0000-0000000039a1') <> 'Nuevo a1' then
    raise exception 'approving with a message must still apply the revision';
  end if;
end
$$;

-- 4) reading: the owner sees her message, the other therapist sees nothing / lectura: la dueña lo ve, la otra terapeuta no
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039a1","role":"authenticated"}', true);
do $$
begin
  if (select approval_note from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039a1') is distinct from 'Hola, aprobé tu perfil.' then
    raise exception 'the owner must read her message';
  end if;
  -- she cannot write it (no column grant) / no puede escribirlo (sin permiso de columna)
  begin
    update public.profile_revisions set approval_note = 'inventado' where id = '30000000-0000-0000-0000-0000000039a1';
    raise exception 'a therapist must not write approval_note';
  exception when insufficient_privilege then null; end;
end
$$;
reset role;
reset session authorization;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039b2","role":"authenticated"}', true);
do $$
begin
  if exists (select 1 from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039a1') then
    raise exception 'another therapist must not see this revision';
  end if;
  -- b2 cannot delete a1's message (reported as nothing to delete) / b2 no puede borrar el mensaje de a1
  begin perform public.delete_my_approval_note('30000000-0000-0000-0000-0000000039a1'); raise exception 'a foreign message must not be deletable';
  exception when sqlstate 'P0002' then null; end;
  -- b2 has no message either / b2 tampoco tiene mensaje
  begin perform public.delete_my_approval_note('30000000-0000-0000-0000-0000000039b2'); raise exception 'nothing to delete must be refused';
  exception when sqlstate 'P0002' then null; end;
end
$$;
reset role;
reset session authorization;

-- 5) the administrator is not the owner: she cannot delete it either / el admin no es la dueña: tampoco puede borrarlo
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039ad","role":"authenticated"}', true);
do $$
begin
  begin perform public.delete_my_approval_note('30000000-0000-0000-0000-0000000039a1'); raise exception 'only the owner deletes the message';
  exception when sqlstate 'P0002' then null; end;
end
$$;
reset role;
reset session authorization;

-- 6) the owner deletes it; a second time there is nothing left / la dueña lo borra; la segunda vez no queda nada
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000039a1","role":"authenticated"}', true);
select public.delete_my_approval_note('30000000-0000-0000-0000-0000000039a1');
do $$
begin
  begin perform public.delete_my_approval_note('30000000-0000-0000-0000-0000000039a1'); raise exception 'a second deletion must be refused';
  exception when sqlstate 'P0002' then null; end;
  begin perform public.delete_my_approval_note(null); raise exception 'a null id must be refused';
  exception when sqlstate '22023' then null; end;
end
$$;
reset role;
reset session authorization;

-- 7) as owner of the database: only the message went away; and the table refuses a message on an open or a rejected revision
-- 7) como dueño de la base: solo se fue el mensaje; y la tabla rechaza un mensaje en una revisión abierta o rechazada
do $$
begin
  if exists (select 1 from public.profile_revisions where id = '30000000-0000-0000-0000-0000000039a1' and approval_note is not null) then
    raise exception 'the message must be gone';
  end if;
  if not exists (select 1 from public.profile_revisions r where r.id = '30000000-0000-0000-0000-0000000039a1' and r.closed_at is not null
                 and r.status_id = (select id from public.revision_statuses where code = 'approved')) then
    raise exception 'deleting the message must not change the revision';
  end if;
end
$$;
select pg_temp.open_revision('30000000-0000-0000-0000-0000000039c3', 'a1', '{"headline":"Otro a1"}'::jsonb);
do $$
begin
  begin
    update public.profile_revisions set approval_note = 'no corresponde' where id = '30000000-0000-0000-0000-0000000039c3';
    raise exception 'an open revision must not carry a message';
  exception when check_violation then null; end;
end
$$;

rollback;
\echo 'OK: the approval message behaves as designed / el mensaje de aprobación se comporta como se diseñó'
