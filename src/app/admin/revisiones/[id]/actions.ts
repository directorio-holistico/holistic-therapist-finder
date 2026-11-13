"use server";

// Approve or reject ONE revision. The database decides who may do it (is_admin() inside approve_revision / reject_revision,
// plus "you cannot approve your own profile"); this code only checks the form and explains the result.
// Aprueba o rechaza UNA revisión. La base decide quién puede (is_admin() dentro de approve_revision / reject_revision, y
// "no podés aprobar tu propio perfil"); este código solo revisa el formulario y explica el resultado.

import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/admin/guard";
import { decisionFacts } from "@/lib/admin/revision-view";

export type DecisionState = { status: "idle" | "error"; message: string };
const fail = (message: string): DecisionState => ({ status: "error", message });

const idSchema = z.uuid();
const reasonSchema = z.string().transform((value) => value.trim()).pipe(z.string().min(1, "Escribí el motivo del rechazo.").max(1000, "El motivo admite hasta 1000 caracteres."));

// Same message for any database refusal: the details stay in the server log. / Un mensaje por rechazo de la base; el detalle queda en el log.
function explain(error: { code?: string; message: string }, action: string): DecisionState {
  console.error(`${action} failed / falló ${action}: ${error.code ?? "unknown"}`);
  if (error.code === "42501") return fail("No se pudo: no sos administrador, o es tu propio perfil (no podés aprobarlo).");
  if (error.code === "55000") return fail("Esa revisión ya no está pendiente. Volvé a la lista.");
  if (error.code === "23514" || error.code === "22023") return fail("Hay un dato de la revisión que la base no acepta (por ejemplo un enlace con formato inválido). Rechazala con ese motivo.");
  return fail("No pudimos completar la acción. Probá de nuevo en unos minutos.");
}

export async function approveRevision(_previous: DecisionState, formData: FormData): Promise<DecisionState> {
  const { supabase } = await requireAdmin();
  const id = idSchema.safeParse(formData.get("revisionId"));
  if (!id.success) return fail("Revisión inválida.");

  const revision = await supabase.from("profile_revisions").select("payload").eq("id", id.data).maybeSingle();
  if (revision.error || !revision.data) return fail("No pudimos leer la revisión.");
  const types = await supabase.from("contact_types").select("id, code").limit(100);
  if (types.error) return fail("No pudimos leer los tipos de contacto.");
  const facts = decisionFacts(revision.data.payload, new Map((types.data ?? []).map((type) => [type.id, type.code])));
  if (!facts) return fail("El contenido de la revisión no tiene el formato esperado: rechazala.");
  if (!facts.hasCity) return fail("Todavía no tiene ciudad. Cargá la ciudad primero (o rechazala pidiendo que elija una).");
  if (facts.linksToCheck > 0 && formData.get("linksChecked") !== "on") return fail("Marcá que revisaste los enlaces antes de aprobar.");

  const result = await supabase.rpc("approve_revision", { p_revision_id: id.data });
  if (result.error) return explain(result.error, "approve_revision");
  redirect("/admin/revisiones?resultado=aprobada");
}

export async function rejectRevision(_previous: DecisionState, formData: FormData): Promise<DecisionState> {
  const { supabase } = await requireAdmin();
  const id = idSchema.safeParse(formData.get("revisionId"));
  if (!id.success) return fail("Revisión inválida.");
  const reason = reasonSchema.safeParse(formData.get("reason") ?? "");
  if (!reason.success) return fail(reason.error.issues[0]?.message ?? "Revisá el motivo.");

  const result = await supabase.rpc("reject_revision", { p_revision_id: id.data, p_reason: reason.data });
  if (result.error) return explain(result.error, "reject_revision");
  redirect("/admin/revisiones?resultado=rechazada");
}
