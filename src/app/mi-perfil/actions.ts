"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePassword } from "@/lib/auth/password-gate";
import { buildAcceptancePayload } from "@/lib/legal/acceptance";
import { loadPendingDocuments } from "@/lib/legal/pending";
import { createServerSupabase } from "@/lib/supabase/server-client";

export async function signOut(): Promise<void> {
  const supabase = await createServerSupabase();
  await supabase.auth.signOut();
  redirect("/ingresar");
}

// Accepts the new versions of the documents the DATABASE says are pending, with the versions published by this deploy.
// The database validates the keys and the versions (accept_current_documents); nothing about it comes from the browser.
// Acepta las versiones nuevas de los documentos que la BASE dice que están pendientes, con las versiones publicadas por este
// despliegue. La base valida las claves y las versiones (accept_current_documents); nada de esto viene del navegador.
export async function acceptNewVersions(): Promise<void> {
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  const pending = await loadPendingDocuments(supabase);
  if (!pending) redirect("/mi-perfil?aceptacion=error");
  if (pending.length > 0) {
    const accepted = await supabase.rpc("accept_current_documents", { p_acceptances: buildAcceptancePayload(pending) });
    if (accepted.error) {
      console.error(`accept_current_documents failed / falló accept_current_documents: ${accepted.error.code ?? "unknown"}`);
      redirect("/mi-perfil?aceptacion=error");
    }
  }
  revalidatePath("/mi-perfil");
  revalidatePath("/mi-perfil/editar");
  redirect("/mi-perfil");
}
