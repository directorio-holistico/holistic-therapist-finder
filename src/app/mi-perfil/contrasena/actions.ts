"use server";

// Saves the password the person chose (first login by link, or "forgot my password"). The password goes straight to Supabase
// Auth, which stores only a hash; it is never logged, stored by us, or sent anywhere else.
// Guarda la contraseña elegida (primer ingreso por enlace, o "olvidé mi contraseña"). Va directo a Supabase Auth, que guarda solo
// un hash; nunca se registra en logs, ni la guardamos nosotros, ni se envía a otro lado.

import { redirect } from "next/navigation";
import { newPasswordSchema, passwordErrorMessage } from "@/lib/auth/password";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type PasswordState = { status: "idle" | "error"; message: string };

export async function setPassword(_previous: PasswordState, formData: FormData): Promise<PasswordState> {
  const parsed = newPasswordSchema.safeParse({ password: formData.get("password"), confirm: formData.get("confirm") });
  if (!parsed.success) return { status: "error", message: parsed.error.issues[0]?.message ?? "Revisá la contraseña." };

  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");

  // First remember the fingerprint of the CURRENT hash: "has a password" means the hash changed after this point.
  // Primero se recuerda la huella del hash ACTUAL: "tiene contraseña" significa que el hash cambió después de este punto.
  const baseline = await supabase.rpc("current_user_has_password");
  if (baseline.error) {
    console.error(`password baseline failed / falló la huella inicial: ${baseline.error.code ?? "unknown"}`);
    return { status: "error", message: passwordErrorMessage(undefined) };
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    console.error(`set password failed / falló guardar la contraseña: ${error.code ?? error.status ?? "unknown"}`);
    return { status: "error", message: passwordErrorMessage(error.code) };
  }
  redirect("/mi-perfil");
}
