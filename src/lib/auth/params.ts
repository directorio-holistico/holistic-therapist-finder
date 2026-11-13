// Pure helpers for the email-link login (easy to test). / Funciones puras del ingreso por enlace al mail (fáciles de probar).

import { z } from "zod";

export const DEFAULT_AFTER_LOGIN = "/mi-perfil";

// Only a path inside this site is accepted as a destination ("/x", never "//x", "/\x" or "https://…"): otherwise a crafted
// link could send the person to another site right after logging in (open redirect).
// Solo se acepta como destino una ruta de este sitio: si no, un enlace armado podría mandar a la persona a otro sitio
// justo después de ingresar (redirección abierta).
export function safeNextPath(value: unknown, fallback: string = DEFAULT_AFTER_LOGIN): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 200) return fallback;
  if (!value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return fallback;
  if (/[\u0000-\u001f\u007f]/.test(value)) return fallback;
  return value;
}

export const loginSchema = z.object({
  email: z
    .string()
    .trim()
    .toLowerCase()
    .max(254)
    .pipe(z.email()),
});

// The three types the email link can carry (new account, existing account, older name of the same link).
// Los tres tipos que puede traer el enlace del mail (cuenta nueva, cuenta existente, nombre viejo del mismo enlace).
export const confirmSchema = z.object({
  token_hash: z.string().min(8).max(300).regex(/^\S+$/),
  type: z.enum(["email", "magiclink", "signup"]),
  next: z.string().optional(),
});
