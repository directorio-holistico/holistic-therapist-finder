// Public address of a profile photo. The photos live in a PUBLIC Storage bucket (the public pages are cached, so a signed link would expire).
// Dirección pública de la foto de un perfil. Las fotos viven en un bucket PÚBLICO de Storage (las páginas públicas se cachean: un enlace firmado vencería).

export const PHOTO_BUCKET = "profile-photos-public";

// Same rule the database enforces: "<profile uuid>/<clean file name>". Anything else is ignored (null), never built into a URL.
// La misma regla que exige la base: "<uuid del perfil>/<nombre de archivo limpio>". Cualquier otra cosa se ignora (null), nunca se arma una URL.
const PHOTO_PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[A-Za-z0-9/_.-]{1,200}$/i;

export function photoPublicUrl(supabaseUrl: string, path: string | null | undefined): string | null {
  if (!path || !PHOTO_PATH.test(path) || path.includes("..")) return null;
  let origin: string;
  try {
    origin = new URL(supabaseUrl).origin;
  } catch {
    return null;
  }
  return `${origin}/storage/v1/object/public/${PHOTO_BUCKET}/${path}`;
}
