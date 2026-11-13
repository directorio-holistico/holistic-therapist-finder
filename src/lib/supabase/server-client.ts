// Supabase client for Server Components, Server Actions and Route Handlers: PUBLIC key + the visitor's session cookie.
// What the person can read or write is decided by the database (RLS), never by this code. The service-role key is not used here.
// Cliente de Supabase para Server Components, Server Actions y Route Handlers: clave PÚBLICA + cookie de sesión.
// Lo que la persona puede leer o escribir lo decide la base (RLS), nunca este código. Acá no se usa la clave service-role.

import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { SESSION_COOKIE_OPTIONS } from "@/lib/auth/cookie-options";
import { getPublicEnv } from "@/lib/env";
import type { Database } from "@/lib/supabase/database.types";

export async function createServerSupabase() {
  const cookieStore = await cookies();
  const { supabaseUrl, supabaseAnonKey } = getPublicEnv();
  return createServerClient<Database>(supabaseUrl, supabaseAnonKey, {
    cookieOptions: SESSION_COOKIE_OPTIONS,
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (list) => {
        try {
          for (const { name, value, options } of list) cookieStore.set(name, value, options);
        } catch {
          // Called from a Server Component, which cannot write cookies: proxy.ts refreshes the session instead.
          // Llamado desde un Server Component, que no puede escribir cookies: la sesión la renueva proxy.ts.
        }
      },
    },
  });
}
