// Read-only client with the PUBLIC key and no session: the patient has no account, and the database decides what the
// anonymous role may read (catalogs, public views and the search function; see docs/supabase-setup.md).
// Typed with the schema generated from the real database (scripts/db/Gen-Types.ps1).
// Cliente de solo lectura con la clave PÚBLICA y sin sesión: el paciente no tiene cuenta, y la base decide qué puede
// leer el rol anónimo (catálogos, vistas públicas y la función de búsqueda; ver docs/supabase-setup.md).
// Tipado con el esquema generado desde la base real (scripts/db/Gen-Types.ps1).

import { createClient } from "@supabase/supabase-js";
import { getPublicEnv } from "@/lib/env";
import type { Database } from "@/lib/supabase/database.types";

export function createAnonClient() {
  const { supabaseUrl, supabaseAnonKey } = getPublicEnv();
  return createClient<Database>(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
