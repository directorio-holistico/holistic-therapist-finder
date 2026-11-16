-- Profile photos, part 2: private bucket for photos waiting for review, and the photo consent as legal evidence.
-- SECURITY CHANGE: 1 private bucket, 1 row in a catalog, 1 callable function.
-- Fotos de perfil, parte 2: bucket privado para fotos en espera de revisión, y el consentimiento de la foto como evidencia legal.
-- CAMBIO DE SEGURIDAD: 1 bucket privado, 1 fila en un catálogo, 1 función invocable.
--
-- Rules / Reglas:
--   * Bucket "profile-photos-pending": PRIVATE (public = false), 500 KB, JPEG or WebP. NO policy on storage.objects: anon and
--     authenticated can neither list, read, upload nor delete. Only the server (service role) touches it, with a path it builds
--     itself ("<profile id>/<uuid>.jpg"), never one that comes from the browser.
--     Bucket PRIVADO, 500 KB, JPEG o WebP. SIN política en storage.objects: anon y authenticated no pueden listar, leer, subir
--     ni borrar. Solo lo toca el servidor (service role), con una ruta que arma él mismo, nunca una que venga del navegador.
--   * New legal document "photo_consent" (optional, so registering is not blocked): "the photo is mine and I authorize showing
--     it". It uses the same evidence table as the other documents (terms_acceptances): person, version of the text, date,
--     and withdrawal date. The evidence cannot be edited; it can only be withdrawn (the existing guard trigger enforces it).
--     Nuevo documento legal "photo_consent" (opcional, para no bloquear el alta): "la foto es mía y autorizo mostrarla". Usa la
--     misma tabla de evidencia que los demás (terms_acceptances): persona, versión del texto, fecha y fecha de retiro. La
--     evidencia no se edita; solo se retira (el trigger de guarda que ya existe lo exige).
--   * set_photo_consent(value, version): the logged-in person gives (with the version shown) or withdraws her own consent.
--     Same shape and checks as set_offers_consent. EXECUTE only for authenticated. SECURITY DEFINER with a fixed search_path.
--     set_photo_consent(valor, versión): la persona con sesión da (con la versión mostrada) o retira su propio consentimiento.
--     Misma forma y controles que set_offers_consent. EXECUTE solo para authenticated. SECURITY DEFINER con search_path fijo.
--   * No new table, column or policy. / Sin tabla, columna ni política nuevas.
--   * The local test database has no "storage" schema: there the bucket step is skipped with a notice (CI keeps working).
--     La base local de pruebas no tiene el esquema "storage": ahí el paso del bucket se omite con un aviso.
--   * Idempotent. / Idempotente.

-- 1) Private bucket / Bucket privado
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found (local database): bucket skipped / no se encontró el esquema storage (base local): bucket omitido';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('profile-photos-pending', 'profile-photos-pending', false, 512000, array['image/jpeg', 'image/webp'])
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
end
$$;

-- 2) The document in the catalog (optional) / El documento en el catálogo (opcional)
insert into public.legal_document_types (code, is_required, sort_order)
values ('photo_consent', false, 5)
on conflict (code) do nothing;

-- 3) Give or withdraw the photo consent / Dar o retirar el consentimiento de la foto
create function public.set_photo_consent(p_value boolean, p_version text default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  person  uuid := public.current_person_id();
  type_id smallint;
begin
  if person is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'a value is required' using errcode = '22023';
  end if;
  select id into strict type_id from public.legal_document_types where code = 'photo_consent' and is_active;
  perform 1 from public.people where id = person for update;  -- serialize the same person's calls

  if p_value then
    if p_version is null or p_version !~ '^[A-Za-z0-9._-]{1,40}$' then
      raise exception 'a valid document version is required' using errcode = '22023';
    end if;
    if not exists (select 1 from public.terms_acceptances
                   where person_id = person and document_type_id = type_id and version = p_version and revoked_at is null) then
      -- a consent given for an older text stays as history; the new text gets its own row
      -- un consentimiento dado para un texto anterior queda como historia; el texto nuevo tiene su propia fila
      insert into public.terms_acceptances (person_id, document_type_id, version) values (person, type_id, p_version);
    end if;
  else
    update public.terms_acceptances set revoked_at = now()
      where person_id = person and document_type_id = type_id and revoked_at is null;
  end if;
end
$$;
revoke execute on function public.set_photo_consent(boolean, text) from public, anon, service_role;
grant execute on function public.set_photo_consent(boolean, text) to authenticated;
