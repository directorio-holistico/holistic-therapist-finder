// Keeps the login session fresh. It runs ONLY on the login and account pages: the public search never goes through here,
// so it stays fast and cacheable. It calls getUser(), which asks the auth server to validate the token.
// Mantiene fresca la sesión. Corre SOLO en las páginas de ingreso y de cuenta: la búsqueda pública no pasa por acá, así
// sigue rápida y cacheable. Llama a getUser(), que le pide al servidor de autenticación validar el token.

import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE_OPTIONS } from "@/lib/auth/cookie-options";
import { getPublicEnv } from "@/lib/env";

export async function proxy(request: NextRequest) {
  const { supabaseUrl, supabaseAnonKey } = getPublicEnv();
  let response = NextResponse.next({ request });
  const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
    cookieOptions: SESSION_COOKIE_OPTIONS,
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list, headers) => {
        for (const { name, value } of list) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of list) response.cookies.set(name, value, options);
        for (const [key, value] of Object.entries(headers)) response.headers.set(key, value);
      },
    },
  });
  await supabase.auth.getUser();
  return response;
}

export const config = {
  matcher: ["/ingresar", "/mi-perfil/:path*", "/auth/:path*"],
};
