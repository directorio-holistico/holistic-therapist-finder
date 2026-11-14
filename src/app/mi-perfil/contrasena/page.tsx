// Choose (or change) the password. After the first email-link login this is the required next step; it is also where the
// "forgot my password" link lands. It needs a session but NOT an existing password (that is the whole point).
// Elegir (o cambiar) la contraseña. Tras el primer ingreso por enlace es el paso obligatorio siguiente; también es donde cae
// el enlace de "olvidé mi contraseña". Pide sesión pero NO una contraseña previa (de eso se trata).

import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { PasswordForm } from "./password-form";

export const metadata: Metadata = { title: "Elegí tu contraseña", robots: { index: false } };

async function Gate() {
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  return <PasswordForm />;
}

export default function PasswordPage() {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Elegí tu contraseña</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">
        Con ella vas a ingresar la próxima vez, sin esperar un mail. Si un día la olvidás, podés pedir un enlace para elegir otra.
      </p>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Gate />
      </Suspense>
    </main>
  );
}
