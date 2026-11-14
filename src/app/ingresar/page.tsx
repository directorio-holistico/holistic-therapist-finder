// Login page for therapists (patients never need an account). Three modes: password (default), first time (email link) and
// "forgot my password". / Página de ingreso de terapeutas (los pacientes no necesitan cuenta). Tres modos: contraseña (por
// defecto), primera vez (enlace al mail) y "olvidé mi contraseña".

import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ForgotPasswordForm, FirstTimeForm, PasswordLoginForm } from "./login-form";

export const metadata: Metadata = { title: "Ingresar · Terapeutas" };

type PageProps = { searchParams: Promise<{ error?: string | string[]; modo?: string | string[] }> };

async function Content({ searchParams }: PageProps) {
  const { error, modo } = await searchParams;
  const mode = modo === "nuevo" || modo === "olvide" ? modo : "clave";
  const linkProblem = error === "enlace";
  const LINK = "underline";
  return (
    <>
      {linkProblem && (
        <p role="alert" className="mt-4 rounded-md border border-red-700 p-3 text-red-800 dark:text-red-300">
          El enlace no es válido o ya venció. Pedí uno nuevo acá abajo.
        </p>
      )}
      {mode === "clave" && (
        <>
          <p className="mt-2 text-zinc-700 dark:text-zinc-300">Ingresá con tu mail y tu contraseña.</p>
          <PasswordLoginForm />
          <p className="mt-6 text-sm text-zinc-700 dark:text-zinc-300">
            <Link className={LINK} href="/ingresar?modo=olvide">Olvidé mi contraseña</Link>
            {" · "}
            <Link className={LINK} href="/ingresar?modo=nuevo">Es mi primera vez</Link>
          </p>
        </>
      )}
      {mode === "nuevo" && (
        <>
          <p className="mt-2 text-zinc-700 dark:text-zinc-300">Para sumarte al directorio: la cuenta se crea al enviarte el enlace.</p>
          <FirstTimeForm />
          <p className="mt-6 text-sm text-zinc-700 dark:text-zinc-300">¿Ya tenés cuenta? <Link className={LINK} href="/ingresar">Ingresá con tu contraseña</Link></p>
        </>
      )}
      {mode === "olvide" && (
        <>
          <p className="mt-2 text-zinc-700 dark:text-zinc-300">Si tenés una cuenta, te enviamos un enlace para elegir una contraseña nueva.</p>
          <ForgotPasswordForm />
          <p className="mt-6 text-sm text-zinc-700 dark:text-zinc-300"><Link className={LINK} href="/ingresar">Volver a ingresar</Link></p>
        </>
      )}
    </>
  );
}

export default function LoginPage(props: PageProps) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Ingresar como terapeuta</h1>
      <Suspense fallback={null}>
        <Content {...props} />
      </Suspense>
    </main>
  );
}
