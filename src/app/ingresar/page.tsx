// Login page for therapists (patients never need an account). Three modes: password (default), first time (email link) and
// "forgot my password". / Página de ingreso de terapeutas (los pacientes no necesitan cuenta). Tres modos: contraseña (por
// defecto), primera vez (enlace al mail) y "olvidé mi contraseña".

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { afterLoginPath } from "@/lib/auth/params";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { ForgotPasswordForm, FirstTimeForm, PasswordLoginForm } from "./login-form";

export const metadata: Metadata = { title: "Ingresar · Terapeutas" };

type PageProps = { searchParams: Promise<{ error?: string | string[]; modo?: string | string[] }> };

async function Content({ searchParams }: PageProps) {
  const { error, modo } = await searchParams;
  const mode = modo === "nuevo" || modo === "olvide" ? modo : "clave";
  const linkProblem = error === "enlace";
  const LINK = "text-acento underline underline-offset-4";
  const ALERT_LINK = "font-medium underline underline-offset-4";
  // Someone who is already logged in does not need the login form: send them where a login would (administrators to the panel,
  // everybody else to their profile). Only the default mode, and not when the link failed (that message must be seen).
  // The session is read on a real request (it checks the token's expiry), and /ingresar goes through proxy.ts, which renews it.
  // Quien ya está ingresado no necesita el formulario: se lo manda adonde iría tras ingresar (administración al panel, el resto
  // a su perfil). Solo en el modo por defecto, y no cuando falló el enlace (ese mensaje tiene que verse). La sesión se lee en un
  // pedido real (revisa el vencimiento del token), y /ingresar pasa por proxy.ts, que la renueva.
  if (mode === "clave" && !linkProblem) {
    await connection();
    const supabase = await createServerSupabase();
    const { data: auth } = await supabase.auth.getUser();
    if (auth.user) {
      const { data: isAdmin } = await supabase.rpc("is_admin");
      redirect(afterLoginPath(isAdmin));
    }
  }
  return (
    <>
      {linkProblem && (
        <div role="alert" className="mt-4 rounded-xl border border-peligro-borde bg-peligro-fondo p-4 text-peligro-texto">
          <p>El enlace no es válido, ya venció o ya se usó (cada enlace sirve una sola vez).</p>
          <p className="mt-2">
            Si ya confirmaste tu mail, ingresá con tu mail y tu contraseña. Si todavía no elegiste una contraseña o no la recordás, tocá{" "}
            <Link className={ALERT_LINK} href="/ingresar?modo=olvide">Olvidé mi contraseña</Link> y te mandamos un enlace para elegirla. Si es tu
            primera vez, tocá <Link className={ALERT_LINK} href="/ingresar?modo=nuevo">Es mi primera vez</Link>.
          </p>
        </div>
      )}
      {mode === "clave" && (
        <>
          <p className="mt-2 text-apagado">Ingresá con tu mail y tu contraseña.</p>
          <PasswordLoginForm />
          <p className="mt-6 text-sm text-apagado">
            <Link className={LINK} href="/ingresar?modo=olvide">Olvidé mi contraseña</Link>
            {" · "}
            <Link className={LINK} href="/ingresar?modo=nuevo">Es mi primera vez</Link>
          </p>
        </>
      )}
      {mode === "nuevo" && (
        <>
          <p className="mt-2 text-apagado">Para sumarte al directorio: la cuenta se crea al enviarte el enlace.</p>
          <FirstTimeForm />
          <p className="mt-6 text-sm text-apagado">¿Ya tenés cuenta? <Link className={LINK} href="/ingresar">Ingresá con tu contraseña</Link></p>
        </>
      )}
      {mode === "olvide" && (
        <>
          <p className="mt-2 text-apagado">Si tenés una cuenta, te enviamos un enlace para elegir una contraseña nueva.</p>
          <ForgotPasswordForm />
          <p className="mt-6 text-sm text-apagado"><Link className={LINK} href="/ingresar">Volver a ingresar</Link></p>
        </>
      )}
    </>
  );
}

export default function LoginPage(props: PageProps) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="font-display text-3xl font-semibold text-tinta">Ingresar como terapeuta</h1>
      <Suspense fallback={null}>
        <Content {...props} />
      </Suspense>
    </main>
  );
}
