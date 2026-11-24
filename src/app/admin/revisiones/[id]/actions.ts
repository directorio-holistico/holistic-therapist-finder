"use server";

// Approve or reject ONE revision. The database decides who may do it (is_admin() inside approve_revision / reject_revision,
// plus "you cannot approve your own profile"); this code only checks the form and explains the result.
// Aprueba o rechaza UNA revisión. La base decide quién puede (is_admin() dentro de approve_revision / reject_revision, y
// "no podés aprobar tu propio perfil"); este código solo revisa el formulario y explica el resultado.

import { redirect } from "next/navigation";
import { z } from "zod";
import { readApprovalNote } from "@/lib/admin/approval-note";
import { requireAdmin } from "@/lib/admin/guard";
import { decisionFacts } from "@/lib/admin/revision-view";
import { isPendingPhotoPath, photoChangeOf } from "@/lib/photo-rules";
import { copyPendingToPublic, removePendingPhoto, removePublicPhoto } from "@/lib/photo-storage";

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

  const revision = await supabase.from("profile_revisions").select("payload, profile_id").eq("id", id.data).maybeSingle();
  if (revision.error || !revision.data) return fail("No pudimos leer la revisión.");
  const types = await supabase.from("contact_types").select("id, code").limit(100);
  if (types.error) return fail("No pudimos leer los tipos de contacto.");
  const facts = decisionFacts(revision.data.payload, new Map((types.data ?? []).map((type) => [type.id, type.code])), revision.data.profile_id);
  if (!facts) return fail("El contenido de la revisión no tiene el formato esperado: rechazala.");
  if (!facts.photoOk) return fail("La foto de la revisión tiene una ruta inválida: rechazala.");
  if (!facts.hasCity) return fail("Todavía no tiene ciudad. Cargá la ciudad primero (o rechazala pidiendo que elija una).");
  if (facts.linksToCheck > 0 && formData.get("linksChecked") !== "on") return fail("Marcá que revisaste los enlaces antes de aprobar.");
  // Optional message for the therapist (she reads it in "Mi perfil"). Checked BEFORE the photo is copied: a refusal changes nothing.
  // Mensaje opcional para la terapeuta (lo lee en "Mi perfil"). Se revisa ANTES de copiar la foto: un rechazo no cambia nada.
  const note = readApprovalNote(formData.get("note"));
  if (!note.ok) return fail(note.message);

  // PHOTO. The pending file is copied to the public bucket BEFORE approving: if the copy fails nothing changes. If approving fails
  // afterwards, the copy is deleted. The path must be a pending file of this very profile (never trust the payload).
  // FOTO. El archivo pendiente se copia al bucket público ANTES de aprobar: si la copia falla no cambia nada. Si aprobar falla
  // después, se borra la copia. La ruta tiene que ser un archivo pendiente de este mismo perfil (el payload nunca es de confianza).
  const change = photoChangeOf(revision.data.payload);
  if (change.kind === "set") {
    if (!isPendingPhotoPath(change.path, revision.data.profile_id)) return fail("La foto de la revisión tiene una ruta inválida: rechazala.");
    if (!(await copyPendingToPublic(change.path))) return fail("No pudimos preparar la foto. Probá de nuevo en unos minutos; no se aprobó nada.");
  }
  const before = change.kind === "none" ? null : await supabase.from("therapist_profiles").select("photo_path").eq("id", revision.data.profile_id).maybeSingle();
  const oldPhoto = before?.data?.photo_path ?? null;

  const result = await supabase.rpc("approve_revision", { p_revision_id: id.data, ...(note.value === null ? {} : { p_note: note.value }) });
  if (result.error) {
    if (change.kind === "set") await removePublicPhoto(change.path);
    return explain(result.error, "approve_revision");
  }
  // Approved: now the old public photo and the pending file are no longer needed. A failure here only leaves a stray file.
  // Aprobada: la foto pública vieja y el archivo pendiente ya no hacen falta. Un fallo acá solo deja un archivo suelto.
  if (change.kind === "set") await removePendingPhoto(change.path);
  if (change.kind !== "none" && oldPhoto && !(change.kind === "set" && oldPhoto === change.path)) await removePublicPhoto(oldPhoto);
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
  // Rejected: the pending photo is KEPT, so the therapist corrects the same proposal and does not lose the picture. It is deleted
  // later: when the therapist uploads another one or discards it, or when the proposal is approved.
  // Rechazada: la foto pendiente se CONSERVA, así el terapeuta corrige la misma propuesta y no pierde la imagen. Se borra después:
  // cuando sube otra o la descarta, o cuando se aprueba la propuesta.
  redirect("/admin/revisiones?resultado=rechazada");
}
