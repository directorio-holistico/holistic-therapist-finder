"use server";

// Saves the profile as a DRAFT revision, or saves and sends it to review. The live profile never changes here: only an
// approved revision changes it (the moderation step). Everything is read with the therapist's own session (RLS).
// Guarda el perfil como revisión BORRADOR, o guarda y lo envía a revisión. El perfil vigente nunca cambia acá: solo lo cambia
// una revisión aprobada (paso de moderación). Todo se lee con la sesión del propio terapeuta (RLS).

import { redirect } from "next/navigation";
import { listFormCatalogs } from "@/lib/catalogs";
import { buildPayload, firstIssue, readProfileForm } from "@/lib/profile-form";
import { contactTypeIds } from "@/lib/profile-load";
import type { Database } from "@/lib/supabase/database.types";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type EditState = {
  status: "idle" | "error" | "saved" | "submitted";
  message: string;
  fields: string[];
  flagged: string[];
};
const fail = (message: string, fields: string[] = []): EditState => ({ status: "error", message, fields, flagged: [] });

export async function saveProfile(_previous: EditState, formData: FormData): Promise<EditState> {
  const intent = formData.get("intent") === "submit" ? "submit" : "save";
  const parsed = readProfileForm(formData, new Date().getFullYear());
  if (!parsed.success) {
    const issue = firstIssue(parsed.error);
    return fail(issue.message, issue.fields);
  }
  const values = parsed.data;

  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");

  const profile = await supabase.from("therapist_profiles").select("id, status_id").maybeSingle();
  if (profile.error) return fail("No pudimos leer tu perfil. Probá de nuevo en unos minutos.");
  if (!profile.data) redirect("/mi-perfil/alta");
  const statuses = await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle();
  if (statuses.data?.code === "suspended" || statuses.data?.code === "erased") return fail("Tu perfil no admite cambios.");

  const catalogs = await listFormCatalogs(supabase);
  const contactTypes = contactTypeIds(catalogs);
  if (!contactTypes) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");

  // 1) The open revision: none -> create a draft; draft -> update it; pending -> locked.
  // 1) La revisión abierta: ninguna -> se crea un borrador; borrador -> se actualiza; en revisión -> bloqueada.
  const open = await supabase.from("profile_revisions").select("id, status_id").is("closed_at", null).maybeSingle();
  if (open.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  if (open.data) {
    const revisionStatus = await supabase.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
    if (revisionStatus.data?.code !== "draft") return fail("Tu perfil ya está en revisión: no se puede cambiar hasta que lo revisemos.");
  }

  // 2) The city typed by hand (or its removal), BEFORE the draft, so a failure here leaves nothing half done.
  // 2) La ciudad escrita a mano (o su baja), ANTES del borrador, para que un fallo no deje nada a medias.
  const request = await supabase.from("location_requests").select("id").is("resolved_at", null).maybeSingle();
  if (request.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  if (values.cityMissing && values.regionId !== null && values.cityName !== null) {
    const written = request.data
      ? await supabase.from("location_requests").update({ region_id: values.regionId, city_name: values.cityName }).eq("id", request.data.id)
      : await supabase.from("location_requests").insert({ profile_id: profile.data.id, region_id: values.regionId, city_name: values.cityName });
    if (written.error) {
      console.error(`location request failed / falló el pedido de ciudad: ${written.error.code ?? "unknown"}`);
      return fail("No pudimos guardar tu ciudad. Revisá la región y el nombre, o probá de nuevo.");
    }
  } else if (request.data) {
    const removed = await supabase.from("location_requests").delete().eq("id", request.data.id);
    if (removed.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  }

  // 3) The draft. / El borrador.
  const payload = buildPayload(values, contactTypes);
  let revisionId = open.data?.id ?? null;
  if (revisionId) {
    const updated = await supabase.from("profile_revisions").update({ payload }).eq("id", revisionId);
    if (updated.error) {
      console.error(`draft update failed / falló la actualización del borrador: ${updated.error.code ?? "unknown"}`);
      return fail("No pudimos guardar el borrador. Probá de nuevo en unos minutos.");
    }
  } else {
    // The generated Insert type asks for status_id, but API roles cannot write it (column-level grants): a trigger fills in
    // "draft". So the row is typed by hand with ONLY the two columns the therapist may write.
    // El tipo Insert generado pide status_id, pero los roles de la API no pueden escribirlo (permisos por columna): un trigger
    // pone "draft". Por eso la fila se tipa a mano con SOLO las dos columnas que el terapeuta puede escribir.
    const draft = { profile_id: profile.data.id, payload } as unknown as Database["public"]["Tables"]["profile_revisions"]["Insert"];
    const created = await supabase.from("profile_revisions").insert(draft).select("id").single();
    if (created.error || !created.data) {
      console.error(`draft insert failed / falló la creación del borrador: ${created.error?.code ?? "unknown"}`);
      return fail("No pudimos guardar el borrador. Probá de nuevo en unos minutos.");
    }
    revisionId = created.data.id;
  }

  if (intent === "save") return { status: "saved", message: "Guardamos tu borrador. Todavía no se envió a revisión.", fields: [], flagged: [] };

  // 4) Send to review. The restricted terms only FLAG the revision (the administrator sees them); they never block it.
  // 4) Enviar a revisión. Los términos restringidos solo MARCAN la revisión (los ve el administrador); nunca la bloquean.
  const submitted = await supabase.rpc("submit_revision", { p_revision_id: revisionId });
  if (submitted.error) {
    console.error(`submit_revision failed / falló submit_revision: ${submitted.error.code ?? "unknown"}`);
    return fail("Guardamos el borrador, pero no pudimos enviarlo a revisión. Probá de nuevo.");
  }
  const flagged = Array.isArray(submitted.data) ? submitted.data.filter((term): term is string => typeof term === "string") : [];
  return { status: "submitted", message: "Enviamos tu perfil a revisión.", fields: [], flagged };
}
