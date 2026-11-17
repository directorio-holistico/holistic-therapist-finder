// The account part of the public header: tells a logged-in person that they are logged in, and gives them a way out.
// It does NOT ask Supabase anything: it only looks at whether the session cookie is there. Reading the session on a public page could
// refresh it without being able to save the new cookie (public pages do not go through proxy.ts), which would log the person out.
// So this only shows links; /mi-perfil and /admin still check the real session on the server, as before.
// La parte de cuenta del encabezado público: avisa a quien está ingresado que lo está, y le da una salida.
// NO le pregunta nada a Supabase: solo mira si está la cookie de sesión. Leer la sesión en una página pública podría renovarla sin poder
// guardar la cookie nueva (las páginas públicas no pasan por proxy.ts), y eso cerraría la sesión. Por eso solo muestra enlaces;
// /mi-perfil y /admin siguen verificando la sesión real en el servidor, como antes.

import { cookies } from "next/headers";
import Link from "next/link";
import { signOut } from "@/app/mi-perfil/actions";
import { hasSessionCookie } from "@/lib/auth/session-cookie";

const BUTTON =
  "inline-flex min-h-11 items-center whitespace-nowrap rounded-full border border-tinta px-4 font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";

// What a visitor without a session sees. Also the Suspense fallback, so the static page already carries it.
// Lo que ve un visitante sin sesión. También es el respaldo de Suspense, así la página estática ya lo trae.
export function LoggedOutLink() {
  return (
    <Link href="/ingresar" className={BUTTON}>
      Soy terapeuta
    </Link>
  );
}

export async function HeaderAccount() {
  const store = await cookies();
  if (!hasSessionCookie(store.getAll().map((cookie) => cookie.name))) return <LoggedOutLink />;
  return (
    <>
      <Link href="/mi-perfil" className={BUTTON}>
        Mi cuenta
      </Link>
      <form action={signOut}>
        <button type="submit" className="inline-flex min-h-11 items-center rounded-md px-3 font-medium text-tinta hover:underline focus-visible:outline-2 focus-visible:outline-acento">
          Salir
        </button>
      </form>
    </>
  );
}
