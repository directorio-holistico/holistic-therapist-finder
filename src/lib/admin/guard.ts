// Who may enter /admin. The page never decides alone: the database function is_admin() answers from the logged-in session,
// and every decision (approve, reject) is checked again inside the database. A person who is not an administrator gets a
// plain "not found", so the panel does not even confirm that it exists.
// Quién puede entrar a /admin. La página nunca decide sola: la función is_admin() de la base responde con la sesión, y cada
// decisión (aprobar, rechazar) se vuelve a verificar dentro de la base. Quien no es administrador recibe un "no encontrado".

import "server-only";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { createServerSupabase } from "@/lib/supabase/server-client";

export async function requireAdmin() {
  // reads the session (token expiry): real requests only / lee la sesión (vencimiento del token): solo pedidos reales
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  const { data: isAdmin, error } = await supabase.rpc("is_admin");
  if (error || isAdmin !== true) notFound();
  return { supabase, userId: auth.user.id };
}
