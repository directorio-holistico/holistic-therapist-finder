// Login page for therapists (patients never need an account). / Página de ingreso de terapeutas (los pacientes no necesitan cuenta).

import type { Metadata } from "next";
import { Suspense } from "react";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Ingresar · Terapeutas" };

type PageProps = { searchParams: Promise<{ error?: string | string[] }> };

async function LinkProblem({ searchParams }: PageProps) {
  const { error } = await searchParams;
  if (error !== "enlace") return null;
  return (
    <p role="alert" className="mt-4 rounded-md border border-red-700 p-3 text-red-800 dark:text-red-300">
      El enlace no es válido o ya venció. Pedí uno nuevo acá abajo.
    </p>
  );
}

export default function LoginPage(props: PageProps) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Ingresar como terapeuta</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">Para sumarte al directorio o editar tu perfil. Si todavía no tenés cuenta, se crea al enviarte el enlace.</p>
      <Suspense fallback={null}>
        <LinkProblem {...props} />
      </Suspense>
      <LoginForm />
    </main>
  );
}
