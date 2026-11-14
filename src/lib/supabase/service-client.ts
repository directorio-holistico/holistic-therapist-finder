// Supabase client with the SECRET (service role) key. It exists for ONE thing: the contact reveal, which only the website
// server may call (ADR-0003). It bypasses RLS, so it is created per call, used for that one function and never passed around.
// Cliente de Supabase con la clave SECRETA (service role). Existe para UNA cosa: el revelado de contacto, que solo puede llamar el
// servidor de la web (ADR-0003). Saltea RLS, así que se crea en cada llamada, se usa para esa función y no se pasa a ningún lado.

import "server-only";
import { createClient } from "@supabase/supabase-js";
import { getPublicEnv } from "@/lib/env";
import type { ServerEnv } from "@/lib/server-env";
import type { Database } from "@/lib/supabase/database.types";

export function createServiceClient(env: Pick<ServerEnv, "serviceRoleKey">) {
  const { supabaseUrl } = getPublicEnv();
  return createClient<Database>(supabaseUrl, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
