"use server";

// Sends the login link. The answer is the SAME whether or not the email already has an account (nobody can use this form
// to find out who is registered). Nothing personal is logged. Limits on sending are Supabase's own for now (ADR-0003 pending).
// Envía el enlace de ingreso. La respuesta es LA MISMA exista o no la cuenta (nadie puede usar este formulario para saber
// quién está registrado). No se registra nada personal. Los límites de envío son los de Supabase por ahora (ADR-0003 pendiente).

import { DEFAULT_AFTER_LOGIN, loginSchema } from "@/lib/auth/params";
import { getSiteUrl } from "@/lib/env";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type LoginState = { status: "idle" | "sent" | "error"; message: string };

export async function sendLoginLink(_previous: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = loginSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { status: "error", message: "Escribí un mail válido, por ejemplo nombre@dominio.com." };

  const supabase = await createServerSupabase();
  // The link in the mail comes back to /auth/callback (same browser: PKCE). Supabase only accepts addresses on its allow list.
  // El enlace del mail vuelve a /auth/callback (mismo navegador: PKCE). Supabase solo acepta direcciones de su lista permitida.
  const emailRedirectTo = `${getSiteUrl()}/auth/callback?next=${encodeURIComponent(DEFAULT_AFTER_LOGIN)}`;
  const { error } = await supabase.auth.signInWithOtp({ email: parsed.data.email, options: { shouldCreateUser: true, emailRedirectTo } });
  if (error) {
    console.error(`login link failed / falló el enlace de ingreso: ${error.code ?? error.status ?? "unknown"}`);
    return { status: "error", message: "No pudimos enviar el enlace ahora. Probá de nuevo en unos minutos." };
  }
  return { status: "sent", message: "Si el mail es correcto, te enviamos un enlace para ingresar. Revisá también la carpeta de spam." };
}
