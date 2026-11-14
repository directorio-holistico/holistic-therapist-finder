"use server";

// Three ways in (decision 37): mail + password (the normal one), an email LINK for the first time (the account is created
// when the link is asked for), and "forgot my password" (an email link that leads to choosing a new one).
// Every answer is the SAME whether or not the email has an account (nobody can use these forms to find out who is
// registered). Nothing personal and no password is ever logged. Limits on sending are Supabase's own for now (ADR-0003 pending).
// Tres formas de entrar (decisión 37): mail + contraseña (la normal), un ENLACE al mail la primera vez (la cuenta se crea al
// pedir el enlace) y "olvidé mi contraseña" (un enlace al mail que lleva a elegir una nueva).
// Cada respuesta es LA MISMA exista o no la cuenta. Nunca se registra nada personal ni contraseñas.

import { redirect } from "next/navigation";
import { passwordLoginSchema } from "@/lib/auth/password";
import { DEFAULT_AFTER_LOGIN, loginSchema } from "@/lib/auth/params";
import { getSiteUrl } from "@/lib/env";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type LoginState = { status: "idle" | "sent" | "error"; message: string };

const LATER = "No pudimos enviar el enlace ahora. Probá de nuevo en unos minutos.";
const SENT = "Si el mail es correcto, te enviamos un enlace. Revisá también la carpeta de spam.";

// 1) First time: the link creates the account if needed. After it, the person must choose a password (see password-gate).
// 1) Primera vez: el enlace crea la cuenta si hace falta. Después, la persona debe elegir una contraseña.
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
    return { status: "error", message: LATER };
  }
  return { status: "sent", message: SENT };
}

// 2) Forgot my password: never creates an account; the link lands on the "choose your password" page.
// 2) Olvidé mi contraseña: nunca crea una cuenta; el enlace cae en la página de "elegí tu contraseña".
export async function sendPasswordReset(_previous: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = loginSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { status: "error", message: "Escribí un mail válido, por ejemplo nombre@dominio.com." };

  const supabase = await createServerSupabase();
  const redirectTo = `${getSiteUrl()}/auth/callback?next=${encodeURIComponent("/mi-perfil/contrasena")}`;
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, { redirectTo });
  if (error) {
    console.error(`password reset failed / falló el enlace de recuperación: ${error.code ?? error.status ?? "unknown"}`);
    return { status: "error", message: LATER };
  }
  return { status: "sent", message: SENT };
}

// 3) The normal login. One generic message for a wrong mail OR a wrong password.
// 3) El ingreso normal. Un solo mensaje genérico para mail incorrecto O contraseña incorrecta.
export async function signInWithPassword(_previous: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = passwordLoginSchema.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) return { status: "error", message: "Escribí tu mail y tu contraseña." };

  const supabase = await createServerSupabase();
  const { error } = await supabase.auth.signInWithPassword({ email: parsed.data.email, password: parsed.data.password });
  if (error) {
    console.error(`password login failed / falló el ingreso con contraseña: ${error.code ?? error.status ?? "unknown"}`);
    if (error.code === "over_request_rate_limit") return { status: "error", message: "Hiciste muchos intentos. Esperá unos minutos y probá de nuevo." };
    return { status: "error", message: "El mail o la contraseña no son correctos." };
  }
  redirect(DEFAULT_AFTER_LOGIN);
}
