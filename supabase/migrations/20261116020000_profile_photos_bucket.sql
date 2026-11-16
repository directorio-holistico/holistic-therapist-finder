-- Public Storage bucket for profile photos. SECURITY CHANGE: it creates a PUBLIC bucket (no listing, no writes through the API).
-- Bucket público de Storage para las fotos de perfil. CAMBIO DE SEGURIDAD: crea un bucket PÚBLICO (sin listado, sin escritura por la API).
--
-- Rules / Reglas:
--   * Bucket "profile-photos-public": public = true so the public pages (cached) can show the photo by a plain address.
--     Excepción a la regla de buckets privados, documentada acá: las páginas públicas se cachean y un enlace firmado vencería.
--     Exception to the private-bucket rule, documented here: public pages are cached and a signed link would expire.
--   * NO policy is created on storage.objects: with row security on and no policy, anon and authenticated can neither LIST nor
--     UPLOAD nor DELETE. A public bucket still serves a file to whoever knows its exact address. Only the server (service role)
--     and the Supabase dashboard write files. / NO se crea política en storage.objects: con RLS activa y sin política, anon y
--     authenticated no pueden listar, subir ni borrar. Un bucket público igual entrega un archivo a quien conoce su dirección
--     exacta. Solo el servidor (service role) y el panel de Supabase escriben archivos.
--   * Only small images: 500 KB per file, JPEG or WebP. The app re-encodes to a square of at most 512 px without metadata.
--     Solo imágenes chicas: 500 KB por archivo, JPEG o WebP. La app recodifica a un cuadrado de hasta 512 px sin metadatos.
--   * File path = "<profile id>/<file name>": the same rule apply_revision_payload already enforces on photo_path.
--     Ruta del archivo = "<id del perfil>/<nombre>": la misma regla que apply_revision_payload ya exige en photo_path.
--   * No new table, column or function: therapist_profiles.photo_path already exists and is already in both public views.
--     Sin tabla, columna ni función nuevas: therapist_profiles.photo_path ya existe y ya está en las dos vistas públicas.
--   * The local test database has no "storage" schema: there the step is skipped with a notice (CI keeps working).
--     La base local de pruebas no tiene el esquema "storage": ahí el paso se omite con un aviso (el CI sigue andando).
--   * Idempotent: running it twice leaves the same result. / Idempotente: correrla dos veces deja el mismo resultado.

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found (local database): bucket skipped / no se encontró el esquema storage (base local): bucket omitido';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('profile-photos-public', 'profile-photos-public', true, 512000, array['image/jpeg', 'image/webp'])
  on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
end
$$;
