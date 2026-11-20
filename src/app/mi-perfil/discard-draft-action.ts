"use server";

// Discards the person's OWN open draft (the database function checks again that it is theirs and that it is still open).
// It never touches Storage: no photo is deleted here, neither the public one nor a pending one. A pending photo is replaced the
// next time the person uploads another one, or removed by the orphan clean-up.
// Descarta el borrador abierto de la PROPIA persona (la función de la base vuelve a comprobar que es suyo y que sigue abierto).
// Nunca toca Storage: acá no se borra ninguna foto, ni la pública ni una pendiente. Una foto pendiente se reemplaza la próxima vez
// que la persona suba otra, o la quita la limpieza de huérfanas.

import { redirect } from "next/navigation";
import { requirePassword } from "@/lib/auth/password-gate";
import { ACCEPTANCE_REQUIRED_MESSAGE, isAcceptanceRequired } from "@/lib/legal/acceptance";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type DiscardState = { status: "idle" | "error"; message: string };
const fail = (message: string): DiscardState => ({ status: "error", message });
const RETRY = "No pudimos descartar el borrador. Probá de nuevo en unos minutos.";

export async function discardDraft(_previous: DiscardState): Promise<DiscardState> {
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  // an administrator can read every profile: filter by the logged-in person / un administrador puede leer todos los perfiles: se filtra por la persona
  const person = await supabase.from("people").select("id").eq("auth_user_id", auth.user.id).maybeSingle();
  if (person.error) return fail(RETRY);
  if (!person.data) redirect("/mi-perfil/alta");
  const profile = await supabase.from("therapist_profiles").select("id").eq("person_id", person.data.id).maybeSingle();
  if (profile.error) return fail(RETRY);
  if (!profile.data) redirect("/mi-perfil/alta");

  // Only a DRAFT is discarded here; a revision already sent to review is not touched. / Acá solo se descarta un BORRADOR; una revisión ya enviada no se toca.
  const open = await supabase.from("profile_revisions").select("id, status_id").eq("profile_id", profile.data.id).is("closed_at", null).maybeSingle();
  if (open.error) return fail(RETRY);
  if (!open.data) redirect("/mi-perfil");
  const status = await supabase.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
  if (status.error) return fail(RETRY);
  if (status.data?.code !== "draft") redirect("/mi-perfil");

  const discarded = await supabase.rpc("discard_revision", { p_revision_id: open.data.id });
  if (isAcceptanceRequired(discarded.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
  if (discarded.error) {
    console.error(`discard_revision failed / falló discard_revision: ${discarded.error.code ?? "unknown"}`);
    return fail(RETRY);
  }
  redirect("/mi-perfil");
}
