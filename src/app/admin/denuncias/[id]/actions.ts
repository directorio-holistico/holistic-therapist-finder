"use server";

// The three decisions on a report: close it, suspend the profile, reinstate the profile. They are SEPARATE on purpose (closing a
// report never changes the profile: suspending is an explicit decision). The database decides who may do each one (is_admin()
// inside the function) and leaves the trace; this code only checks the form and explains the result.
// Las tres decisiones sobre una denuncia: cerrarla, suspender el perfil, reponer el perfil. Son APARTE a propósito (cerrar una
// denuncia nunca cambia el perfil: suspender es una decisión explícita). La base decide quién puede cada una (is_admin() dentro
// de la función) y deja el registro; este código solo revisa el formulario y explica el resultado.

import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/admin/guard";
import { parseReportId } from "@/lib/admin/report-view";

export type ActionState = { status: "idle" | "error"; message: string };
const fail = (message: string): ActionState => ({ status: "error", message });

const text = (max: number, empty: string) =>
  z.string().transform((value) => value.trim()).pipe(z.string().min(1, empty).max(max, `Admite hasta ${max} caracteres.`));
const noteSchema = text(1000, "Escribí la nota de cierre.");
const suspendReasonSchema = text(500, "Escribí el motivo de la suspensión.");
const reinstateReasonSchema = text(1000, "Escribí el motivo de la reposición.");
const closeStatusSchema = z.enum(["dismissed", "resolved"]);
const profileIdSchema = z.uuid();

// One message per database refusal; the detail stays in the server log. / Un mensaje por rechazo de la base; el detalle queda en el log.
function explain(error: { code?: string; message: string }, action: string, stateMessage: string): ActionState {
  console.error(`${action} failed / falló ${action}: ${error.code ?? "unknown"}`);
  if (error.code === "42501") return fail("No se pudo: no sos administrador.");
  if (error.code === "55000") return fail(stateMessage);
  if (error.code === "P0002") return fail("No se encontró lo que querías cambiar. Volvé a la lista.");
  if (error.code === "22023") return fail("La base no acepta algún dato del formulario. Revisalo.");
  return fail("No pudimos completar la acción. Probá de nuevo en unos minutos.");
}

export async function closeReport(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase } = await requireAdmin();
  const reportId = parseReportId(String(formData.get("reportId") ?? ""));
  if (reportId === null) return fail("Denuncia inválida.");
  const status = closeStatusSchema.safeParse(formData.get("status"));
  if (!status.success) return fail("Elegí cómo cerrar la denuncia.");
  const note = noteSchema.safeParse(formData.get("note") ?? "");
  if (!note.success) return fail(note.error.issues[0]?.message ?? "Revisá la nota.");

  const result = await supabase.rpc("close_report", { p_report_id: reportId, p_status_code: status.data, p_note: note.data });
  if (result.error) return explain(result.error, "close_report", "Esa denuncia ya está cerrada. Volvé a la lista.");
  redirect("/admin/denuncias?resultado=cerrada");
}

export async function suspendProfile(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase } = await requireAdmin();
  const reportId = parseReportId(String(formData.get("reportId") ?? ""));
  const profileId = profileIdSchema.safeParse(formData.get("profileId"));
  if (reportId === null || !profileId.success) return fail("Pedido inválido.");
  if (formData.get("confirm") !== "on") return fail("Marcá la confirmación para suspender el perfil.");
  const reason = suspendReasonSchema.safeParse(formData.get("reason") ?? "");
  if (!reason.success) return fail(reason.error.issues[0]?.message ?? "Revisá el motivo.");

  const result = await supabase.rpc("suspend_profile", { p_profile_id: profileId.data, p_reason: reason.data });
  if (result.error) return explain(result.error, "suspend_profile", "Ese perfil ya está suspendido o eliminado.");
  redirect(`/admin/denuncias/${reportId}?resultado=suspendido`);
}

export async function reinstateProfile(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase } = await requireAdmin();
  const reportId = parseReportId(String(formData.get("reportId") ?? ""));
  const profileId = profileIdSchema.safeParse(formData.get("profileId"));
  if (reportId === null || !profileId.success) return fail("Pedido inválido.");
  const reason = reinstateReasonSchema.safeParse(formData.get("reason") ?? "");
  if (!reason.success) return fail(reason.error.issues[0]?.message ?? "Revisá el motivo.");

  const result = await supabase.rpc("reinstate_profile", { p_profile_id: profileId.data, p_reason: reason.data });
  if (result.error) return explain(result.error, "reinstate_profile", "Solo se puede reponer un perfil suspendido.");
  redirect(`/admin/denuncias/${reportId}?resultado=repuesto`);
}
