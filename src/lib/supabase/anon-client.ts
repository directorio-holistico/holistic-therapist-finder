// Read-only client with the PUBLIC key and no session: the patient has no account, and the database decides what the
// anonymous role may read (catalogs, public views and the search function; see docs/supabase-setup.md).
// Cliente de solo lectura con la clave PÚBLICA y sin sesión: el paciente no tiene cuenta, y la base decide qué puede
// leer el rol anónimo (catálogos, vistas públicas y la función de búsqueda; ver docs/supabase-setup.md).

import { createClient } from "@supabase/supabase-js";
import { getPublicEnv } from "@/lib/env";

export function createAnonClient() {
  const { supabaseUrl, supabaseAnonKey } = getPublicEnv();
  return createClient(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
