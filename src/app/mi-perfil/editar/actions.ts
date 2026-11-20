"use server";

// Saves the profile as a DRAFT revision, or saves and sends it to review. The live profile never changes here: only an
// approved revision changes it (the moderation step). Everything is read with the therapist's own session (RLS).
// Guarda el perfil como revisión BORRADOR, o guarda y lo envía a revisión. El perfil vigente nunca cambia acá: solo lo cambia
// una revisión aprobada (paso de moderación). Todo se lee con la sesión del propio terapeuta (RLS).

import { redirect } from "next/navigation";
import { requirePassword } from "@/lib/auth/password-gate";
import { listFormCatalogs, listLocations } from "@/lib/catalogs";
import { findExistingCity } from "@/lib/city-match";
import { ACCEPTANCE_REQUIRED_MESSAGE, isAcceptanceRequired } from "@/lib/legal/acceptance";
import { isPendingPhotoPath } from "@/lib/photo-rules";
import { buildPayload, firstIssue, readProfileForm } from "@/lib/profile-form";
import { audienceIds, contactTypeIds } from "@/lib/profile-load";
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
  // save = save and keep editing / exit = save and go back to "My profile" / submit = save and send to review
  // save = guardar y seguir editando / exit = guardar y volver a "Mi perfil" / submit = guardar y enviar a revisión
  const wanted = formData.get("intent");
  const intent = wanted === "submit" ? "submit" : wanted === "exit" ? "exit" : "save";
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  // The catalogs come first: the currencies decide how many decimals a rate may have. / Primero los catálogos: las monedas deciden los decimales.
  const catalogs = await listFormCatalogs(supabase);
  const contactTypes = contactTypeIds(catalogs);
  const audiences = audienceIds(catalogs);
  if (!contactTypes || !audiences) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");

  const currencyMinorUnits = new Map(catalogs.currencies.map((currency) => [currency.id, currency.minorUnits]));
  const parsed = readProfileForm(formData, new Date().getFullYear(), currencyMinorUnits);
  if (!parsed.success) {
    const issue = firstIssue(parsed.error);
    return fail(issue.message, issue.fields);
  }
  let values = parsed.data;

  // an administrator can read every profile: filter by the logged-in person / un administrador puede leer todos los perfiles: se filtra por la persona
  const person = await supabase.from("people").select("id").eq("auth_user_id", auth.user.id).maybeSingle();
  if (person.error) return fail("No pudimos leer tu cuenta. Probá de nuevo en unos minutos.");
  if (!person.data) redirect("/mi-perfil/alta");
  const profile = await supabase.from("therapist_profiles").select("id, status_id").eq("person_id", person.data.id).maybeSingle();
  if (profile.error) return fail("No pudimos leer tu perfil. Probá de nuevo en unos minutos.");
  if (!profile.data) redirect("/mi-perfil/alta");
  const statuses = await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle();
  if (statuses.data?.code === "suspended" || statuses.data?.code === "erased") return fail("Tu perfil no admite cambios.");

  // The new photo must be a pending file of THIS profile (made by the server), never a path the browser invented.
  // La foto nueva tiene que ser un archivo pendiente de ESTE perfil (hecho por el servidor), nunca una ruta inventada por el navegador.
  if (values.photoNew !== null && !isPendingPhotoPath(values.photoNew, profile.data.id)) return fail("La foto no es válida. Elegila de nuevo.", ["photo"]);

  // 1) The open revision: none -> create a draft; draft -> update it; pending -> locked.
  // 1) La revisión abierta: ninguna -> se crea un borrador; borrador -> se actualiza; en revisión -> bloqueada.
  const open = await supabase.from("profile_revisions").select("id, status_id").eq("profile_id", profile.data.id).is("closed_at", null).maybeSingle();
  if (open.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  if (open.data) {
    const revisionStatus = await supabase.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
    if (revisionStatus.data?.code !== "draft") return fail("Tu perfil ya está en revisión: no se puede cambiar hasta que lo revisemos.");
  }

  // 1b) A city typed by hand that ALREADY exists in the chosen region (same name, ignoring accents and capitals) is used as is:
  // no request is made for the administrator. If the lookup fails we do not guess: the typed city goes as a request, as before.
  // 1b) Una ciudad escrita a mano que YA existe en la región elegida (mismo nombre, sin importar tildes ni mayúsculas) se usa tal cual:
  // no se hace un pedido al administrador. Si la consulta falla no adivinamos: la ciudad escrita sigue como pedido, como antes.
  if (values.cityMissing && values.regionId !== null && values.cityName !== null) {
    const existing = await listLocations(supabase, values.regionId).then((options) => findExistingCity(options, values.cityName ?? ""), () => null);
    if (existing) values = { ...values, cityMissing: false, cityId: existing.id, cityName: null };
  }

  // 2) The city typed by hand (or its removal), BEFORE the draft, so a failure here leaves nothing half done.
  // 2) La ciudad escrita a mano (o su baja), ANTES del borrador, para que un fallo no deje nada a medias.
  const request = await supabase.from("location_requests").select("id").eq("profile_id", profile.data.id).is("resolved_at", null).maybeSingle();
  if (request.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  if (values.cityMissing && values.regionId !== null && values.cityName !== null) {
    const written = request.data
      ? await supabase.from("location_requests").update({ region_id: values.regionId, city_name: values.cityName }).eq("id", request.data.id)
      : await supabase.from("location_requests").insert({ profile_id: profile.data.id, region_id: values.regionId, city_name: values.cityName });
    if (isAcceptanceRequired(written.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
    if (written.error) {
      console.error(`location request failed / falló el pedido de ciudad: ${written.error.code ?? "unknown"}`);
      return fail("No pudimos guardar tu ciudad. Revisá la región y el nombre, o probá de nuevo.");
    }
  } else if (request.data) {
    const removed = await supabase.from("location_requests").delete().eq("id", request.data.id);
    if (isAcceptanceRequired(removed.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
    if (removed.error) return fail("No pudimos guardar ahora. Probá de nuevo en unos minutos.");
  }

  // 3) The draft. / El borrador.
  const payload = buildPayload(values, contactTypes, audiences);
  let revisionId = open.data?.id ?? null;
  if (revisionId) {
    const updated = await supabase.from("profile_revisions").update({ payload }).eq("id", revisionId);
    if (isAcceptanceRequired(updated.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
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
    if (isAcceptanceRequired(created.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
    if (created.error || !created.data) {
      console.error(`draft insert failed / falló la creación del borrador: ${created.error?.code ?? "unknown"}`);
      return fail("No pudimos guardar el borrador. Probá de nuevo en unos minutos.");
    }
    revisionId = created.data.id;
  }

  // "exit" takes the person back to "My profile", where the state and the next step are written (Continue and send / Discard).
  // "exit" lleva a la persona de vuelta a "Mi perfil", donde están escritos el estado y el próximo paso (Continuar y enviar / Descartar).
  if (intent === "exit") redirect("/mi-perfil?guardado=1");
  if (intent === "save") return { status: "saved", message: "Guardamos tu borrador. Todavía no se envió a revisión.", fields: [], flagged: [] };

  // 4) Send to review. The restricted terms only FLAG the revision (the administrator sees them); they never block it.
  // 4) Enviar a revisión. Los términos restringidos solo MARCAN la revisión (los ve el administrador); nunca la bloquean.
  const submitted = await supabase.rpc("submit_revision", { p_revision_id: revisionId });
  if (isAcceptanceRequired(submitted.error)) return fail(ACCEPTANCE_REQUIRED_MESSAGE);
  if (submitted.error) {
    console.error(`submit_revision failed / falló submit_revision: ${submitted.error.code ?? "unknown"}`);
    return fail("Guardamos el borrador, pero no pudimos enviarlo a revisión. Probá de nuevo.");
  }
  const flagged = Array.isArray(submitted.data) ? submitted.data.filter((term): term is string => typeof term === "string") : [];
  return { status: "submitted", message: "Enviamos tu perfil a revisión.", fields: [], flagged };
}
