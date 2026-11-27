// Small helpers for how a result card looks. No data is read or changed here.
// Pequeñas ayudas para cómo se ve una tarjeta de resultado. Acá no se lee ni se cambia ningún dato.

/** Initials for the avatar: up to two letters, ignoring a leading tag like "[DEMO]". / Iniciales del avatar: hasta dos letras, ignorando una marca inicial como "[DEMO]". */
export function initialsOf(displayName: string): string {
  const words = displayName
    .replace(/^\s*\[[^\]]*\]\s*/, "")
    .split(/\s+/)
    .filter((word) => /\p{L}/u.test(word));
  const letters = words.slice(0, 2).map((word) => (word.match(/\p{L}/u)?.[0] ?? "").toUpperCase());
  const result = letters.join("");
  return result === "" ? "?" : result;
}

/** Keeps the first `max` items and says how many were left out. / Conserva los primeros `max` y dice cuántos quedaron afuera. */
export function capItems<T>(items: readonly T[], max: number): { shown: T[]; hidden: number } {
  const limit = Math.max(0, Math.floor(max));
  return { shown: items.slice(0, limit), hidden: Math.max(0, items.length - limit) };
}

// Countries that have a flag file in public/flags (own copies from flag-icons, MIT). Add a code here when the file is added.
// Países con archivo de bandera en public/flags (copias propias de flag-icons, MIT). Sumar el código acá al agregar el archivo.
const FLAG_CODES: ReadonlySet<string> = new Set(["AR", "MX", "ES", "CL", "UY"]);

/** Public path of the flag for an ISO country code, or null when there is none. / Ruta pública de la bandera de un código ISO de país, o null si no hay. */
export function flagSrc(iso: string | null | undefined): string | null {
  const code = iso?.trim().toUpperCase() ?? "";
  return FLAG_CODES.has(code) ? `/flags/${code.toLowerCase()}.svg` : null;
}
