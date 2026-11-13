// Sign-up form for a logged-in person who has no therapist account yet. If they already have one, go to the profile.
// Formulario de alta para una persona ingresada que todavía no tiene cuenta de terapeuta. Si ya la tiene, va al perfil.

import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { LegalReviewNotice } from "@/components/legal-document";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { RegisterForm } from "./register-form";

export const metadata: Metadata = { title: "Crear mi perfil", robots: { index: false } };

async function Gate() {
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  const { data: person, error } = await supabase.from("people").select("id").maybeSingle();
  if (error) throw new Error(`Could not read the account / No se pudo leer la cuenta: ${error.message}`);
  if (person) redirect("/mi-perfil");
  return <RegisterForm suggestedName="" />;
}

export default function RegisterPage() {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Crear mi perfil de terapeuta</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">
        Es gratis. Tu perfil se publica recién después de que lo revisemos.
      </p>
      <div className="mt-4"><LegalReviewNotice /></div>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Gate />
      </Suspense>
    </main>
  );
}
