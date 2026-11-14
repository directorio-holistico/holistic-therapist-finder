// Rules for the password the person chooses (pure, easy to test). / Reglas de la contraseña que elige la persona (puras, fáciles de probar).
//
// Minimum 10 characters (decided by the owner). Maximum 72 BYTES: the hashing function Supabase uses (bcrypt) only reads the
// first 72 bytes, so a longer text would be silently cut; we refuse it instead. The text is never trimmed or changed.
// Mínimo 10 caracteres (decidido por el dueño). Máximo 72 BYTES: la función de hash de Supabase (bcrypt) solo lee los primeros
// 72 bytes, y un texto más largo se cortaría sin avisar; lo rechazamos. El texto nunca se recorta ni se modifica.
// NOTE: the same minimum must also be set in the Supabase dashboard (Authentication > Sign In / Providers > Password), because
// this check only protects the website; a direct call to the Auth API would not pass through here.
// NOTA: el mismo mínimo debe configurarse en el panel de Supabase, porque esta verificación solo protege la web.

import { z } from "zod";

export const PASSWORD_MIN_LENGTH = 10;
export const PASSWORD_MAX_BYTES = 72;

const byteLength = (value: string) => new TextEncoder().encode(value).length;

export const newPasswordSchema = z
  .object({
    password: z.string(),
    confirm: z.string(),
  })
  .superRefine((value, context) => {
    if ([...value.password].length < PASSWORD_MIN_LENGTH) {
      context.addIssue({ code: "custom", path: ["password"], message: `La contraseña debe tener al menos ${PASSWORD_MIN_LENGTH} caracteres.` });
    } else if (byteLength(value.password) > PASSWORD_MAX_BYTES) {
      context.addIssue({ code: "custom", path: ["password"], message: "La contraseña es demasiado larga (máximo 72 bytes: unos 72 caracteres comunes)." });
    } else if (value.password !== value.confirm) {
      context.addIssue({ code: "custom", path: ["confirm"], message: "Las dos contraseñas no coinciden." });
    }
  });

// What to tell the person when Supabase refuses the new password. Anything unknown gets a neutral message.
// Qué decirle a la persona cuando Supabase rechaza la contraseña. Lo desconocido recibe un mensaje neutro.
export function passwordErrorMessage(code: string | undefined): string {
  if (code === "weak_password") return "Esa contraseña es muy fácil de adivinar. Elegí otra, más larga o menos común.";
  if (code === "same_password") return "Elegí una contraseña distinta de la anterior.";
  if (code === "over_request_rate_limit") return "Hiciste muchos intentos. Esperá unos minutos y probá de nuevo.";
  return "No pudimos guardar tu contraseña ahora. Probá de nuevo en unos minutos.";
}

// Login with mail + password: the mail is cleaned like in the link login; the password is only checked for being present and
// not absurdly long (it is never trimmed). / Ingreso con mail + contraseña.
export const passwordLoginSchema = z.object({
  email: z.string().trim().toLowerCase().max(254).pipe(z.email()),
  password: z.string().min(1).max(200),
});
