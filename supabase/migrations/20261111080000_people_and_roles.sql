-- People and roles. SECURITY CHANGE: 2 new tables, 1 SECURITY DEFINER function, RLS and grants.
-- Personas y roles. CAMBIO DE SEGURIDAD: 2 tablas nuevas, 1 función SECURITY DEFINER, RLS y permisos.
--
-- Rules applied / Reglas aplicadas:
--  * One person = one record (auth_user_id is unique). Roles are rows in person_roles.
--    Una persona = una ficha (auth_user_id es único). Los roles son filas en person_roles.
--  * A person never edits their own record through the API: names and roles change only through
--    server functions or the owner (added in later commits). So there is NO INSERT/UPDATE/DELETE grant,
--    which also makes privilege escalation (giving yourself the admin role) impossible from the API.
--    Una persona nunca edita su ficha por la API: los nombres y roles cambian solo por funciones de
--    servidor o por el dueño (se agregan en commits posteriores). Por eso NO hay permiso de escritura,
--    y eso también impide que alguien se dé a sí mismo el rol de administrador desde la API.
--  * Read access / Lectura:
--      anon:           nothing (no grant at all) / nada (sin ningún permiso)
--      authenticated:  only their own person row and their own roles
--                      solo su propia ficha y sus propios roles
--      admin:          every person and every role / todas las personas y todos los roles
--  * Erasure keeps the row but anonymizes it (see docs/data-model.md, section Erasure):
--    erased_at set, email and auth_user_id cleared. Constraints below enforce that shape.
--    La eliminación conserva la fila pero la anonimiza: erased_at con fecha, mail y auth_user_id vacíos.
--    Las restricciones de abajo exigen esa forma.

create table public.people (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  full_name    text not null check (full_name = btrim(full_name) and char_length(full_name) between 1 and 120),
  email        text check (email = lower(btrim(email)) and char_length(email) between 3 and 254 and email like '%_@_%'),
  created_at   timestamptz not null default now(),
  erased_at    timestamptz,
  -- active person: has an email; erased person: no email and no login link
  -- persona activa: tiene mail; persona eliminada: sin mail y sin vínculo de acceso
  constraint people_erased_shape check (
    (erased_at is null and email is not null)
    or (erased_at is not null and email is null and auth_user_id is null)
  )
);
create unique index people_email_uniq on public.people (email) where email is not null;
comment on table public.people is
  'One record per person (therapist or admin) / Una ficha por persona. Erased people are anonymized, not deleted.';

create table public.person_roles (
  person_id  uuid     not null references public.people (id) on delete cascade,
  role_id    smallint not null references public.roles (id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (person_id, role_id)
);
create index person_roles_role_idx on public.person_roles (role_id);
comment on table public.person_roles is 'Roles of each person / Roles de cada persona.';

-- is_admin(): true when the logged-in user is an active person holding the active admin role.
-- SECURITY DEFINER so the policies can ask it without recursing into the RLS of the same tables.
-- Fixed search_path; reads only; returns false when nobody is logged in.
-- is_admin(): verdadero si el usuario con sesión es una persona activa con el rol admin activo.
-- SECURITY DEFINER para que las políticas la consulten sin entrar en recursión con la RLS de las mismas
-- tablas. search_path fijo; solo lee; devuelve falso si no hay sesión.
create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((
    select true
    from public.people p
    join public.person_roles pr on pr.person_id = p.id
    join public.roles r on r.id = pr.role_id
    where p.auth_user_id = auth.uid()
      and p.erased_at is null
      and r.code = 'admin'
      and r.is_active
    limit 1
  ), false)
$$;

revoke execute on function public.is_admin() from public, anon, service_role;
grant execute on function public.is_admin() to authenticated;

-- ============================================================================
-- SECURITY: RLS + GRANT + policies / SEGURIDAD: RLS + GRANT + políticas
-- ============================================================================

alter table public.people enable row level security;
grant select on public.people to authenticated;
create policy people_select_own on public.people
  for select to authenticated
  using (auth_user_id = (select auth.uid()));
create policy people_select_admin on public.people
  for select to authenticated
  using ((select public.is_admin()));

alter table public.person_roles enable row level security;
grant select on public.person_roles to authenticated;
create policy person_roles_select_own on public.person_roles
  for select to authenticated
  using (exists (
    select 1 from public.people p
    where p.id = person_id and p.auth_user_id = (select auth.uid())
  ));
create policy person_roles_select_admin on public.person_roles
  for select to authenticated
  using ((select public.is_admin()));
