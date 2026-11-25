// Rules for the photo a therapist uploads. Pure (no network, no files) so they are easy to test. A photo goes through two buckets:
// "profile-photos-pending" (PRIVATE, waits for the administrator) and "profile-photos-public" (after approval).
// Reglas de la foto que sube un terapeuta. Puras (sin red ni archivos) para probarlas fácil. La foto pasa por dos buckets:
// "profile-photos-pending" (PRIVADO, espera al administrador) y "profile-photos-public" (tras la aprobación).

export const PHOTO_PENDING_BUCKET = "profile-photos-pending";

export const PHOTO_OUTPUT_SIZE = 512; // final side, in pixels (square) / lado final, en píxeles (cuadrado)
export const PHOTO_MIN_SIDE = 256; // smaller pictures are refused / las imágenes más chicas se rechazan
export const PHOTO_MAX_UPLOAD_BYTES = 1_000_000; // the browser already shrinks the picture: this is a safety limit / el navegador ya la achica: es un tope de seguridad
export const PHOTO_MAX_INPUT_PIXELS = 25_000_000; // protects against "decompression bombs" / protege contra "bombas de descompresión"
export const PHOTO_ALLOWED_FORMATS = ["jpeg", "png", "webp"] as const;

// The text the therapist agrees to, and its version. The version is stored next to the acceptance (set_photo_consent): any change of
// wording must change the version. The database accepts 1 to 40 characters: letters, digits, dot, underscore and hyphen.
// El texto que acepta el terapeuta y su versión. La versión se guarda junto a la aceptación (set_photo_consent): todo cambio de
// texto debe cambiar la versión. La base acepta de 1 a 40 caracteres: letras, números, punto, guion bajo y guion.
export const PHOTO_CONSENT_VERSION = "2026-11-a";
export const PHOTO_CONSENT_TEXT =
  "Declaro que esta foto es mía y autorizo que se muestre en mi perfil público de Faro Holístico. Puedo retirar esta autorización cuando quiera quitando la foto.";

// Shown when the person tries to save or send while a picture is chosen but not uploaded yet (otherwise it would be silently left out).
// Se muestra cuando la persona intenta guardar o enviar con una imagen elegida pero todavía sin subir (si no, quedaría afuera sin avisar).
export const PHOTO_UNCONFIRMED_MESSAGE =
  "Elegiste una foto pero todavía no la subiste. Tildá la autorización y apretá «Subir esta foto» (o «Cancelar» si no la querés). Después guardá o enviá.";

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const UUID_RE = new RegExp(`^${UUID}$`, "i");
const PENDING_PATH_RE = new RegExp(`^(${UUID})/(${UUID})\\.jpg$`, "i");

// "<profile id>/<file id>.jpg". Both ids must be UUIDs: the path is always built by the server, never taken from the browser.
// "<id del perfil>/<id del archivo>.jpg". Ambos ids son UUID: la ruta la arma siempre el servidor, nunca el navegador.
export function pendingPhotoPath(profileId: string, fileId: string): string | null {
  return UUID_RE.test(profileId) && UUID_RE.test(fileId) ? `${profileId.toLowerCase()}/${fileId.toLowerCase()}.jpg` : null;
}

// True only for a pending-photo path inside THIS profile's own folder. / Verdadero solo para una ruta pendiente dentro de la carpeta de ESTE perfil.
export function isPendingPhotoPath(path: unknown, profileId: string): path is string {
  if (typeof path !== "string" || !UUID_RE.test(profileId)) return false;
  const match = PENDING_PATH_RE.exec(path);
  return match !== null && (match[1] ?? "").toLowerCase() === profileId.toLowerCase();
}

// What a stored revision asks for about the photo: nothing (key absent), a new photo (a path) or to remove it (null).
// Lo que pide una revisión guardada sobre la foto: nada (clave ausente), una foto nueva (una ruta) o quitarla (null).
export type PhotoChange = { kind: "none" } | { kind: "set"; path: string } | { kind: "remove" };

export function photoChangeOf(payload: unknown): PhotoChange {
  if (typeof payload !== "object" || payload === null || !("photo_path" in payload)) return { kind: "none" };
  const value = (payload as { photo_path?: unknown }).photo_path;
  if (value === null) return { kind: "remove" };
  return typeof value === "string" && value.length > 0 ? { kind: "set", path: value } : { kind: "none" };
}

// Reasons a picture is refused, in words for the therapist. / Motivos por los que se rechaza una imagen, en palabras para el terapeuta.
export const PHOTO_ERRORS = {
  format: "Esa imagen no se puede usar. Probá con una foto JPG, PNG o WebP.",
  size: "La imagen es muy chica o muy pesada. Probá con otra foto más grande.",
  unreadable: "No pudimos leer esa imagen. Probá con otra.",
  consent: "Marcá la autorización para poder subir la foto.",
  session: "Tu sesión venció. Volvé a ingresar.",
  blocked: "Tu perfil no admite cambios en este momento.",
  locked: "Tu perfil ya está en revisión: no se puede cambiar hasta que lo revisemos.",
  storage: "No pudimos guardar la foto ahora. Probá de nuevo en unos minutos.",
} as const;
export type PhotoErrorCode = keyof typeof PHOTO_ERRORS;
