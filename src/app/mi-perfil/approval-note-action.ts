"use server";

// Deletes the message the administrator left when approving. Only its owner can: the database function checks it again.
// Elimina el mensaje que dejó el administrador al aprobar. Solo puede su dueña: la función de la base lo vuelve a comprobar.

import { redirect } from "next/navigation";
import { z } from "zod";
import { requirePassword } from "@/lib/auth/password-gate";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type ApprovalNoteState = { status: "idle" | "error"; message: string };

export async function deleteApprovalNote(_previous: ApprovalNoteState, formData: FormData): Promise<ApprovalNoteState> {
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  const revisionId = z.uuid().safeParse(formData.get("revisionId"));
  if (!revisionId.success) return { status: "error", message: "Mensaje inválido." };

  const result = await supabase.rpc("delete_my_approval_note", { p_revision_id: revisionId.data });
  // P0002: it was already deleted (another tab, a second click): the goal is reached, so the page just reloads.
  // P0002: ya estaba eliminado (otra pestaña, un segundo clic): el objetivo está cumplido, así que solo se recarga la página.
  if (result.error && result.error.code !== "P0002") {
    console.error(`delete_my_approval_note failed / falló delete_my_approval_note: ${result.error.code ?? "unknown"}`);
    return { status: "error", message: "No pudimos eliminar el mensaje. Probá de nuevo en unos minutos." };
  }
  redirect("/mi-perfil");
}
