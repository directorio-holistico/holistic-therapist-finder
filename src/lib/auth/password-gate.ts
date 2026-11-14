// "Choose your password first" gate. Decision 37: first login by email link, then the person must choose a password before
// using the account. The database answers (current_user_has_password) from the session; this never trusts the browser.
// Puerta de "elegí tu contraseña primero". Decisión 37: primer ingreso por enlace al mail y luego la persona debe elegir una
// contraseña antes de usar la cuenta. La base responde (current_user_has_password) desde la sesión; no se confía en el navegador.

import "server-only";
import { redirect } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";

export const PASSWORD_PAGE = "/mi-perfil/contrasena";

export async function requirePassword(supabase: SupabaseClient<Database>): Promise<void> {
  const { data, error } = await supabase.rpc("current_user_has_password");
  if (error) throw new Error(`Could not check the password step / No se pudo verificar el paso de contraseña: ${error.code ?? "unknown"}`);
  if (data !== true) redirect(PASSWORD_PAGE);
}
