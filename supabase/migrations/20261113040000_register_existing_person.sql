-- register_therapist: also complete the sign-up of a person who already exists but has no therapist profile
-- (for example an administrator who is not yet a therapist). Before this, such a person got "already registered"
-- and was sent in circles between /mi-perfil and /mi-perfil/alta.
-- register_therapist: también completa el alta de una persona que ya existe pero no tiene perfil de terapeuta
-- (por ejemplo un administrador que todavía no es terapeuta). Antes recibía "ya registrado" y daba vueltas
-- entre /mi-perfil y /mi-perfil/alta.
--
-- Rules / Reglas:
--  * A person WITH a profile still gets 23505 "already registered" (nothing changes for them).
--    Una persona CON perfil sigue recibiendo 23505 "ya registrado" (no cambia nada para ellos).
--  * A person WITHOUT a profile keeps their record and name; the function adds the therapist role (if missing), creates
--    the empty UNPUBLISHED profile and records the acceptances (an already active acceptance of the same version is not
--    repeated). Other roles (admin) are untouched.
--    Una persona SIN perfil conserva su ficha y su nombre; se agrega el rol terapeuta (si falta), se crea el perfil vacío
--    SIN PUBLICAR y se registran las aceptaciones (una aceptación activa de la misma versión no se repite). Los otros roles
--    (admin) no se tocan.
--  * Identity still comes from the session (auth.uid()), never from a parameter. Same grants as before.
--    La identidad sigue saliendo de la sesión (auth.uid()), nunca de un parámetro. Mismos permisos que antes.

create or replace function public.register_therapist(p_full_name text, p_acceptances jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  uid          uuid := auth.uid();
  auth_email   text;
  confirmed_at timestamptz;
  name         text := btrim(p_full_name);
  new_person   uuid;
  new_profile  uuid;
  doc          record;
  given        text;
  known_codes  text[];
begin
  if uid is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  select lower(btrim(u.email)), u.email_confirmed_at into auth_email, confirmed_at from auth.users u where u.id = uid;
  if not found or auth_email is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if confirmed_at is null then
    raise exception 'verify your email first' using errcode = '42501';
  end if;

  -- an existing person is locked so two calls cannot both create a profile / se bloquea la persona existente
  select p.id into new_person from public.people p where p.auth_user_id = uid for update;
  if new_person is not null and exists (select 1 from public.therapist_profiles tp where tp.person_id = new_person) then
    raise exception 'already registered' using errcode = '23505';
  end if;

  if name is null or char_length(name) not between 1 and 120 then
    raise exception 'the name must have 1 to 120 characters' using errcode = '22023';
  end if;
  if p_acceptances is null or jsonb_typeof(p_acceptances) <> 'object' then
    raise exception 'acceptances must be an object' using errcode = '22023';
  end if;
  select coalesce(array_agg(code), '{}') into known_codes from public.legal_document_types where is_active;
  if exists (select 1 from jsonb_object_keys(p_acceptances) k where k <> all (known_codes)) then
    raise exception 'unknown document in acceptances' using errcode = '22023';
  end if;

  if new_person is null then
    begin
      insert into public.people (auth_user_id, full_name, email) values (uid, name, auth_email) returning id into new_person;
    exception when unique_violation then
      raise exception 'already registered' using errcode = '23505';
    end;
  end if;
  insert into public.person_roles (person_id, role_id) values (new_person, (select id from public.roles where code = 'therapist'))
    on conflict do nothing;
  begin
    insert into public.therapist_profiles (person_id, status_id)
      values (new_person, (select id from public.profile_statuses where code = 'unpublished'))
      returning id into new_profile;
  exception when unique_violation then
    raise exception 'already registered' using errcode = '23505';
  end;

  for doc in select id, code, is_required from public.legal_document_types where is_active order by sort_order loop
    if jsonb_typeof(p_acceptances -> doc.code) is distinct from 'string' then
      if doc.is_required then
        raise exception 'you must accept the document: %', doc.code using errcode = '22023';
      elsif p_acceptances ? doc.code and jsonb_typeof(p_acceptances -> doc.code) <> 'null' then
        raise exception 'the version of % must be text', doc.code using errcode = '22023';
      end if;
      continue;  -- optional and not given
    end if;
    given := p_acceptances ->> doc.code;
    if given !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'invalid version for %', doc.code using errcode = '22023';
    end if;
    insert into public.terms_acceptances (person_id, document_type_id, version) values (new_person, doc.id, given)
      on conflict (person_id, document_type_id, version) where revoked_at is null do nothing;
  end loop;

  return new_profile;
end
$$;
revoke execute on function public.register_therapist(text, jsonb) from public, anon, service_role;
grant execute on function public.register_therapist(text, jsonb) to authenticated;
