-- The administrator clears a therapy request once the revision is decided: who may, what is refused, what the audit log keeps.
-- El administrador borra un pedido de terapia cuando la revisión ya está decidida: quién puede, qué se rechaza, qué guarda la auditoría.
-- Run after Reset-LocalDb.ps1 / Ejecutar después de Reset-LocalDb.ps1.

begin;

insert into auth.users (id, email, email_confirmed_at)
  select ('00000000-0000-0000-0000-0000000038' || k)::uuid, k || '@example.test', now() from unnest(array['a1','a2','ad']) k;
insert into public.people (id, auth_user_id, full_name, email)
  select ('10000000-0000-0000-0000-0000000038' || k)::uuid, ('00000000-0000-0000-0000-0000000038' || k)::uuid, 'Persona ' || k, k || '@example.test'
  from unnest(array['a1','a2','ad']) k;
insert into public.person_roles (person_id, role_id)
  select '10000000-0000-0000-0000-0000000038ad'::uuid, id from public.roles where code = 'admin';
insert into public.therapist_profiles (id, person_id, status_id)
  select ('20000000-0000-0000-0000-0000000038' || k)::uuid, ('10000000-0000-0000-0000-0000000038' || k)::uuid,
         (select id from public.profile_statuses where code = 'unpublished')
  from unnest(array['a1','a2']) k;
-- a1: a DECIDED (approved) revision with a request; a2: a PENDING one with a request
-- a1: una revisión DECIDIDA (aprobada) con pedido; a2: una PENDIENTE con pedido
insert into public.profile_revisions (id, profile_id, status_id, payload, suggested_therapy, submitted_at, decided_at, closed_at)
  values ('30000000-0000-0000-0000-0000000038a1', '20000000-0000-0000-0000-0000000038a1',
          (select id from public.revision_statuses where code = 'approved'), '{}'::jsonb, 'Coaching transpersonal', now(), now(), now());
insert into public.profile_revisions (id, profile_id, status_id, payload, suggested_therapy, submitted_at, due_at)
  values ('30000000-0000-0000-0000-0000000038a2', '20000000-0000-0000-0000-0000000038a2',
          (select id from public.revision_statuses where code = 'pending_review'), '{}'::jsonb, 'Otra terapia', now(), now() + interval '3 days');

-- 1) ANON: not even the function / ANON: ni la función
set session authorization authenticator;
set role anon;
select set_config('request.jwt.claims', '', true);
do $$
begin
  begin
    perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-0000000038a1');
    raise exception 'anon must not execute admin_dismiss_suggested_therapy';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
reset session authorization;

-- 2) a1 (the therapist, not an administrator): refused / a1 (la terapeuta, no admin): rechazada
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000038a1","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-0000000038a1');
    raise exception 'a non-admin must not dismiss a request';
  exception when sqlstate '42501' then null;
  end;
end
$$;
reset role;
reset session authorization;
do $$
begin
  if (select suggested_therapy from public.profile_revisions where id = '30000000-0000-0000-0000-0000000038a1') is distinct from 'Coaching transpersonal' then
    raise exception 'a refused call must leave the request untouched';
  end if;
end
$$;

-- 3) ad (administrator): refuses an open revision and a missing one, clears a decided one, refuses a second time
-- 3) ad (administrador): rechaza una revisión abierta y una inexistente, limpia una decidida, rechaza la segunda vez
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000038ad","role":"authenticated"}', true);
do $$
begin
  begin perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-0000000038a2'); raise exception 'an open revision must be refused';
  exception when sqlstate '55000' then null; end;
  begin perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-000000000000'); raise exception 'a missing revision must be refused';
  exception when sqlstate 'P0002' then null; end;
  begin perform public.admin_dismiss_suggested_therapy(null); raise exception 'a null id must be refused';
  exception when sqlstate '22023' then null; end;
  perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-0000000038a1');
  begin perform public.admin_dismiss_suggested_therapy('30000000-0000-0000-0000-0000000038a1'); raise exception 'a second dismissal must be refused';
  exception when sqlstate 'P0002' then null; end;
end
$$;
reset role;
reset session authorization;

-- 4) as owner: the decided one is cleared and keeps its other data; the open one still has its request; the audit log says who
-- 4) como dueño: la decidida quedó limpia y conserva lo demás; la abierta conserva su pedido; la auditoría dice quién
do $$
begin
  if exists (select 1 from public.profile_revisions where id = '30000000-0000-0000-0000-0000000038a1' and suggested_therapy is not null) then
    raise exception 'the decided revision must have no request left';
  end if;
  if not exists (select 1 from public.profile_revisions where id = '30000000-0000-0000-0000-0000000038a1' and closed_at is not null) then
    raise exception 'clearing the request must not reopen or change the revision';
  end if;
  if (select suggested_therapy from public.profile_revisions where id = '30000000-0000-0000-0000-0000000038a2') is distinct from 'Otra terapia' then
    raise exception 'the open revision must keep its request';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'profile_revisions' and operation = 'UPDATE'
                 and row_key = '30000000-0000-0000-0000-0000000038a1' and changed_fields = array['suggested_therapy']
                 and actor_person_id = '10000000-0000-0000-0000-0000000038ad') then
    raise exception 'the audit log must record who cleared the request (column name only)';
  end if;
  if exists (select 1 from public.audit_log where detail is not null and table_name = 'profile_revisions') then
    raise exception 'the audit log must never keep the text of the request';
  end if;
end
$$;

rollback;
\echo 'OK: dismissing a therapy request behaves as designed / descartar un pedido de terapia se comporta como se diseñó'
