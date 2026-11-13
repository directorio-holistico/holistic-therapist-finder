"use server";

// Completes the sign-up: calls register_therapist (creates the person, the therapist role, an empty UNPUBLISHED profile and
// the acceptances, all in one transaction). Identity comes from the session in the database, never from the form.
// Completa el alta: llama a register_therapist (crea persona, rol, perfil vacío SIN PUBLICAR y aceptaciones, en una sola
// transacción). La identidad sale de la sesión en la base, nunca del formulario.

import { redirect } from "next/navigation";
import { buildAcceptances, readRegistrationForm, registrationErrorMessage } from "@/lib/registration";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type RegisterState = { status: "idle" | "error"; message: string };

export async function registerTherapist(_previous: RegisterState, formData: FormData): Promise<RegisterState> {
  const parsed = readRegistrationForm(formData);
  if (!parsed.success) {
    return { status: "error", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  }

  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");

  const { error } = await supabase.rpc("register_therapist", {
    p_full_name: parsed.data.fullName,
    p_acceptances: buildAcceptances(parsed.data),
  });
  // 23505 = already registered: the goal is met, go to the profile. / 23505 = ya registrado: el objetivo está cumplido.
  if (error && error.code !== "23505") {
    console.error(`register_therapist failed / falló register_therapist: ${error.code ?? "unknown"}`);
    return { status: "error", message: registrationErrorMessage(error.code) };
  }
  redirect("/mi-perfil");
}
