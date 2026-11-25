// Everything the preview needs, read with the logged-in therapist's OWN session (RLS returns only their rows; reads only, nothing is written).
// The source follows the same rule as the editor: an open revision (draft or in review) first, then the last rejected proposal, then the live profile.
// Todo lo que necesita la vista previa, leído con la sesión del propio terapeuta (RLS devuelve solo sus filas; solo lecturas, no se escribe nada).
// El origen sigue la misma regla que el editor: primero una revisión abierta (borrador o en revisión), luego la última propuesta rechazada, luego el perfil vigente.

import type { SupabaseClient } from "@supabase/supabase-js";
import { getLanguageId, listFormCatalogs, listLocationTree, type FormCatalogs, type LocationTree } from "@/lib/catalogs";
import { audienceIds, contactTypeIds, loadLiveDefaults } from "@/lib/profile-load";
import type { PreviewSource } from "@/lib/profile-preview";
import { defaultsFromPayload, EMPTY_DEFAULTS, type FormDefaults } from "@/lib/profile-form";
import type { Database } from "@/lib/supabase/database.types";

type Client = SupabaseClient<Database>;

export type PreviewData =
  | { kind: "no-account" }
  | { kind: "blocked"; status: string }
  | {
      kind: "ready";
      source: PreviewSource;
      profileId: string;
      defaults: FormDefaults;
      catalogs: FormCatalogs;
      tree: LocationTree;
      countryIso: string | null;
      isPinned: boolean;
      shortNames: Map<number, string>;
      livePhotoPath: string | null;
      profileStatus: string;
    };

function fail(what: string, message: string): never {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
}

export async function loadProfilePreview(client: Client, authUserId: string): Promise<PreviewData> {
  // An administrator can read every row of these tables: filter by the logged-in person explicitly (same as the editor).
  // Un administrador puede leer todas las filas de estas tablas: se filtra explícitamente por la persona ingresada (igual que el editor).
  const person = await client.from("people").select("id").eq("auth_user_id", authUserId).maybeSingle();
  if (person.error) fail("the account / la cuenta", person.error.message);
  if (!person.data) return { kind: "no-account" };
  const profile = await client
    .from("therapist_profiles")
    .select("id, status_id, display_name, headline, about, zone, practice_start_year, location_id, photo_path, is_pinned")
    .eq("person_id", person.data.id)
    .maybeSingle();
  if (profile.error) fail("the profile / el perfil", profile.error.message);
  if (!profile.data) return { kind: "no-account" };

  const status = await client.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle();
  if (status.error) fail("the profile status / el estado del perfil", status.error.message);
  const profileStatus = status.data?.code ?? "";
  if (profileStatus === "suspended" || profileStatus === "erased") return { kind: "blocked", status: profileStatus };

  const [catalogs, tree] = await Promise.all([listFormCatalogs(client), listLocationTree(client)]);
  const contactTypes = contactTypeIds(catalogs);
  if (!contactTypes) fail("contact types / tipos de contacto", "the contact types must exist / los tipos de contacto deben existir");
  const audiences = audienceIds(catalogs);
  if (!audiences) fail("rate audiences / audiencias de tarifa", "own_country and other_countries must exist / deben existir");

  // Which saved version is shown. / Qué versión guardada se muestra.
  let source: PreviewSource = "live";
  let payload: unknown = null;
  let hasPayload = false;
  const open = await client.from("profile_revisions").select("status_id, payload").eq("profile_id", profile.data.id).is("closed_at", null).maybeSingle();
  if (open.error) fail("the open revision / la revisión abierta", open.error.message);
  if (open.data) {
    const revisionStatus = await client.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
    if (revisionStatus.error) fail("the revision status / el estado de la revisión", revisionStatus.error.message);
    source = revisionStatus.data?.code === "pending_review" ? "in_review" : "draft";
    payload = open.data.payload;
    hasPayload = true;
  } else {
    const decided = await client
      .from("profile_revisions")
      .select("payload, rejection_reason")
      .eq("profile_id", profile.data.id)
      .not("decided_at", "is", null)
      .order("decided_at", { ascending: false })
      .limit(1);
    if (decided.error) fail("the last decision / la última decisión", decided.error.message);
    const latest = decided.data?.[0];
    if (latest && latest.rejection_reason !== null) {
      source = "rejected";
      payload = latest.payload;
      hasPayload = true;
    }
  }

  const defaults = hasPayload
    ? defaultsFromPayload(payload, contactTypes, audiences, { ...EMPTY_DEFAULTS, displayName: profile.data.display_name ?? "" })
    : await loadLiveDefaults(client, profile.data, contactTypes, audiences);

  // The flag and the short names are only decoration: if they cannot be read the preview still works (flag-less, with full names).
  // La bandera y los nombres cortos son solo decoración: si no se pueden leer, la vista previa igual funciona (sin bandera, con nombres completos).
  const city = tree.cities.find((option) => option.id === defaults.cityId);
  const region = tree.regions.find((option) => option.id === city?.parentId);
  let countryIso: string | null = null;
  if (region) {
    const country = await client.from("locations").select("iso_code").eq("id", region.parentId).maybeSingle();
    countryIso = country.error ? null : (country.data?.iso_code ?? null);
  }
  const shortNames = new Map<number, string>();
  const therapyIds = defaults.therapies.flatMap((slot) => (slot.therapyId === null ? [] : [slot.therapyId]));
  if (therapyIds.length > 0) {
    const languageId = await getLanguageId(client);
    const shorts = await client.from("therapy_translations").select("therapy_id, short_name").eq("language_id", languageId).in("therapy_id", therapyIds).limit(100);
    if (!shorts.error) for (const row of shorts.data ?? []) if (row.short_name) shortNames.set(row.therapy_id, row.short_name);
  }

  return {
    kind: "ready",
    source,
    profileId: profile.data.id,
    defaults,
    catalogs,
    tree,
    countryIso,
    isPinned: profile.data.is_pinned,
    shortNames,
    livePhotoPath: profile.data.photo_path ?? null,
    profileStatus,
  };
}
