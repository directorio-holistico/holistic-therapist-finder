// Everything the profile editor needs, read with the logged-in therapist's own session (RLS returns only their rows).
// No joins under RLS: each table is read on its own. Every read has an explicit limit.
// Todo lo que necesita el editor de perfil, leído con la sesión del propio terapeuta (RLS devuelve solo sus filas).
// Sin joins bajo RLS: cada tabla se lee por separado. Toda lectura tiene un límite explícito.

import type { SupabaseClient } from "@supabase/supabase-js";
import { listFormCatalogs, listLocationTree, type FormCatalogs, type LocationTree } from "@/lib/catalogs";
import {
  AUDIENCE_CODES, CONTACT_CODES, defaultsFromPayload, EMPTY_DEFAULTS, padTherapies, type AudienceIds, type ContactTypeIds, type FormDefaults,
} from "@/lib/profile-form";
import type { Database } from "@/lib/supabase/database.types";

type Client = SupabaseClient<Database>;

export type EditorData =
  | { kind: "no-account" }
  | { kind: "blocked"; status: string }
  | { kind: "in-review" }
  | {
      kind: "edit";
      defaults: FormDefaults;
      catalogs: FormCatalogs;
      tree: LocationTree;
      contactTypes: ContactTypeIds;
      audiences: AudienceIds;
      initialCountryId: number | null;
      initialRegionId: number | null;
      missingCity: { regionId: number; cityName: string } | null;
      lastRejection: string | null;
    };

function fail(what: string, message: string): never {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
}

export function contactTypeIds(catalogs: FormCatalogs): ContactTypeIds | null {
  const id = (code: string) => catalogs.contactTypes.find((type) => type.code === code)?.id;
  const phone = id(CONTACT_CODES.phone);
  const email = id(CONTACT_CODES.email);
  const website = id(CONTACT_CODES.website);
  const instagram = id(CONTACT_CODES.instagram);
  const facebook = id(CONTACT_CODES.facebook);
  const tiktok = id(CONTACT_CODES.tiktok);
  const youtube = id(CONTACT_CODES.youtube);
  return phone && email && website && instagram && facebook && tiktok && youtube
    ? { phone, email, website, instagram, facebook, tiktok, youtube }
    : null;
}

export function audienceIds(catalogs: FormCatalogs): AudienceIds | null {
  const id = (code: string) => catalogs.rateAudiences.find((audience) => audience.code === code)?.id;
  const own = id(AUDIENCE_CODES.own);
  const other = id(AUDIENCE_CODES.other);
  return own && other ? { own, other } : null;
}

// An administrator can READ every row of these tables (policy *_select_admin), so every "my own data" query is filtered by the
// logged-in person explicitly: without the filter, an administrator who is also a therapist would get several rows.
// Un administrador puede LEER todas las filas de estas tablas (política *_select_admin), por eso cada consulta de "mis datos"
// se filtra explícitamente por la persona ingresada: sin el filtro, un administrador que también es terapeuta recibiría varias filas.
export async function loadProfileEditor(client: Client, authUserId: string): Promise<EditorData> {
  const person = await client.from("people").select("id").eq("auth_user_id", authUserId).maybeSingle();
  if (person.error) fail("the account / la cuenta", person.error.message);
  if (!person.data) return { kind: "no-account" };
  const profile = await client
    .from("therapist_profiles")
    .select("id, status_id, display_name, headline, zone, practice_start_year, location_id")
    .eq("person_id", person.data.id)
    .maybeSingle();
  if (profile.error) fail("the profile / el perfil", profile.error.message);
  if (!profile.data) return { kind: "no-account" };

  const status = await client.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle();
  if (status.error) fail("the profile status / el estado del perfil", status.error.message);
  const statusCode = status.data?.code ?? "";
  if (statusCode === "suspended" || statusCode === "erased") return { kind: "blocked", status: statusCode };

  const open = await client.from("profile_revisions").select("id, status_id, payload").eq("profile_id", profile.data.id).is("closed_at", null).maybeSingle();
  if (open.error) fail("the open revision / la revisión abierta", open.error.message);
  if (open.data) {
    const revisionStatus = await client.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
    if (revisionStatus.error) fail("the revision status / el estado de la revisión", revisionStatus.error.message);
    if (revisionStatus.data?.code === "pending_review") return { kind: "in-review" };
  }

  const [catalogs, tree] = await Promise.all([listFormCatalogs(client), listLocationTree(client)]);
  const contactTypes = contactTypeIds(catalogs);
  if (!contactTypes) fail("contact types / tipos de contacto", "phone, email, website, instagram, facebook, tiktok and youtube must exist (apply the latest migrations) / deben existir (aplicá las últimas migraciones)");

  const audiences = audienceIds(catalogs);
  if (!audiences) fail("rate audiences / audiencias de tarifa", "own_country and other_countries must exist / deben existir");

  // Start from the live profile; a draft in progress replaces it. / Se parte del perfil vigente; un borrador en curso lo reemplaza.
  let defaults: FormDefaults;
  if (open.data) {
    defaults = defaultsFromPayload(open.data.payload, contactTypes, audiences, { ...EMPTY_DEFAULTS, displayName: profile.data.display_name ?? "" });
  } else {
    const [languages, modes, formats, contacts, therapies, rates] = await Promise.all([
      client.from("profile_languages").select("language_id").eq("profile_id", profile.data.id).limit(100),
      client.from("profile_service_modes").select("service_mode_id").eq("profile_id", profile.data.id).limit(100),
      client.from("profile_session_formats").select("session_format_id").eq("profile_id", profile.data.id).limit(100),
      client.from("profile_contacts").select("contact_type_id, value, accepts_whatsapp").eq("profile_id", profile.data.id).limit(100),
      client.from("profile_therapies").select("therapy_id, session_minutes").eq("profile_id", profile.data.id).order("therapy_id").limit(100),
      client.from("profile_therapy_rates").select("therapy_id, rate_audience_id, amount, currency_id").eq("profile_id", profile.data.id).limit(100),
    ]);
    for (const result of [languages, modes, formats, contacts, therapies, rates]) if (result.error) fail("the profile data / los datos del perfil", result.error.message);
    const contact = (id: number) => contacts.data?.find((row) => row.contact_type_id === id);
    const rateRows = rates.data ?? [];
    const rateOf = (therapyId: number, audienceId: number) => rateRows.find((row) => row.therapy_id === therapyId && row.rate_audience_id === audienceId);
    defaults = {
      displayName: profile.data.display_name ?? "",
      headline: profile.data.headline ?? "",
      zone: profile.data.zone ?? "",
      practiceStartYear: profile.data.practice_start_year != null ? String(profile.data.practice_start_year) : "",
      cityId: profile.data.location_id,
      languages: (languages.data ?? []).map((row) => row.language_id),
      serviceModes: (modes.data ?? []).map((row) => row.service_mode_id),
      sessionFormats: (formats.data ?? []).map((row) => row.session_format_id),
      phone: contact(contactTypes.phone)?.value ?? "",
      phoneWhatsapp: contact(contactTypes.phone)?.accepts_whatsapp ?? false,
      email: contact(contactTypes.email)?.value ?? "",
      website: contact(contactTypes.website)?.value ?? "",
      instagram: contact(contactTypes.instagram)?.value ?? "",
      facebook: contact(contactTypes.facebook)?.value ?? "",
      tiktok: contact(contactTypes.tiktok)?.value ?? "",
      youtube: contact(contactTypes.youtube)?.value ?? "",
      therapies: padTherapies(
        (therapies.data ?? []).map((row) => ({
          therapyId: row.therapy_id,
          minutes: row.session_minutes != null ? String(row.session_minutes) : "",
          rateOwn: String(rateOf(row.therapy_id, audiences.own)?.amount ?? ""),
          rateOther: String(rateOf(row.therapy_id, audiences.other)?.amount ?? ""),
        })),
      ),
      currencyOwn: rateRows.find((row) => row.rate_audience_id === audiences.own)?.currency_id ?? null,
      currencyOther: rateRows.find((row) => row.rate_audience_id === audiences.other)?.currency_id ?? null,
    };
  }

  const request = await client.from("location_requests").select("region_id, city_name").eq("profile_id", profile.data.id).is("resolved_at", null).maybeSingle();
  if (request.error) fail("the city request / el pedido de ciudad", request.error.message);
  const missingCity = request.data ? { regionId: request.data.region_id, cityName: request.data.city_name } : null;

  const city = tree.cities.find((option) => option.id === defaults.cityId);
  const regionId = city?.parentId ?? missingCity?.regionId ?? null;
  const region = tree.regions.find((option) => option.id === regionId);

  const rejected = await client
    .from("profile_revisions")
    .select("rejection_reason")
    .eq("profile_id", profile.data.id)
    .not("rejection_reason", "is", null)
    .order("decided_at", { ascending: false })
    .limit(1);
  if (rejected.error) fail("the last rejection / el último rechazo", rejected.error.message);

  return {
    kind: "edit",
    defaults,
    catalogs,
    tree,
    contactTypes,
    audiences,
    initialCountryId: region?.parentId ?? null,
    initialRegionId: regionId,
    missingCity,
    lastRejection: open.data ? (rejected.data?.[0]?.rejection_reason ?? null) : null,
  };
}
