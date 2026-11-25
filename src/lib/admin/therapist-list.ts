// Reads the therapist list with the ADMINISTRATOR's session (RLS applies; no service role). Several small queries, no nested joins.
// It reads only what the page shows: no phone number (just whether a WhatsApp link can be built); the account e-mail is read but
// the view keeps it only for people who never saved anything.
// Lee la lista de terapeutas con la sesión del ADMINISTRADOR (rige RLS; sin service role). Varias consultas chicas, sin joins anidados.
// Lee solo lo que muestra la página: ni número de teléfono (solo si se puede armar un enlace de WhatsApp); el mail de la cuenta se lee
// pero la vista lo conserva solo de quien nunca guardó nada.

import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CATALOG_LANGUAGE_CODE } from "@/lib/catalogs";
import type { Database } from "@/lib/supabase/database.types";
import { chunksOf } from "@/lib/admin/followup-view";
import {
  countryIdOf,
  latestRevisionStatus,
  toTherapistRow,
  type ContactStub,
  type PersonStub,
  type ProfileStub,
  type RevisionLite,
  type TherapistRow,
} from "@/lib/admin/therapist-list-view";

type Client = SupabaseClient<Database>;

const PAGE_SIZE = 1000; // the API returns at most 1,000 rows per request / la API devuelve como mucho 1.000 filas por pedido
const MAX_PAGES = 10;
const CHUNK = 40; // ids per request, so the address stays short / ids por pedido, para que la dirección no sea larga

const fail = (what: string, message: string): never => {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
};

export type TherapistList = { rows: TherapistRow[]; complete: boolean };

export async function loadTherapistList(client: Client): Promise<TherapistList> {
  const nowMs = Date.now();

  const profileStatuses = await client.from("profile_statuses").select("id, code").limit(50);
  if (profileStatuses.error) return fail("the profile statuses", profileStatuses.error.message);
  const profileCode = new Map(profileStatuses.data.map((row) => [row.id, row.code]));

  const revisionStatuses = await client.from("revision_statuses").select("id, code").limit(50);
  if (revisionStatuses.error) return fail("the revision statuses", revisionStatuses.error.message);
  const revisionCode = new Map(revisionStatuses.data.map((row) => [row.id, row.code]));
  const discardedId = revisionStatuses.data.find((row) => row.code === "discarded")?.id ?? null;

  const contactTypes = await client.from("contact_types").select("id, code").eq("code", "phone").limit(5);
  if (contactTypes.error) return fail("the contact types", contactTypes.error.message);
  const phoneTypeId = contactTypes.data[0]?.id ?? null;

  const validity = await client.rpc("rates_validity_months");
  if (validity.error || typeof validity.data !== "number") return fail("the rates validity setting", validity.error?.message ?? "not a number");
  const months = validity.data as number;

  // All profiles, page by page. / Todos los perfiles, de a páginas.
  const profiles: ProfileStub[] = [];
  let complete = false;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data, error } = await client
      .from("therapist_profiles")
      .select("id, person_id, display_name, status_id, location_id, rates_confirmed_at")
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    if (error) return fail("the profiles", error.message);
    profiles.push(...data);
    if (data.length < PAGE_SIZE) {
      complete = true;
      break;
    }
  }

  // Light read of ALL revisions (no payload) to know each profile's latest one. / Lectura liviana de TODAS las revisiones (sin payload).
  const revisions: RevisionLite[] = [];
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data, error } = await client
      .from("profile_revisions")
      .select("profile_id, status_id, created_at")
      .order("created_at", { ascending: false })
      .order("id", { ascending: true })
      .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    if (error) return fail("the revisions", error.message);
    revisions.push(...data);
    if (data.length < PAGE_SIZE) break;
    if (page === MAX_PAGES - 1) complete = false;
  }
  const latest = latestRevisionStatus(revisions, discardedId);

  const people = new Map<string, PersonStub>();
  for (const ids of chunksOf([...new Set(profiles.map((profile) => profile.person_id))], CHUNK)) {
    const { data, error } = await client.from("people").select("id, full_name, email, created_at, erased_at").in("id", ids).limit(CHUNK);
    if (error) return fail("the people", error.message);
    for (const row of data) people.set(row.id, row);
  }

  const contacts = new Map<string, ContactStub[]>();
  if (phoneTypeId !== null) {
    for (const ids of chunksOf(profiles.map((profile) => profile.id), CHUNK)) {
      const { data, error } = await client
        .from("profile_contacts")
        .select("profile_id, contact_type_id, value, accepts_whatsapp")
        .eq("contact_type_id", phoneTypeId)
        .in("profile_id", ids)
        .limit(CHUNK * 10);
      if (error) return fail("the contacts", error.message);
      for (const row of data) contacts.set(row.profile_id, [...(contacts.get(row.profile_id) ?? []), row]);
    }
  }

  // Country of each profile: walk the location tree upwards (city > region > country), one level per round.
  // País de cada perfil: se sube por el árbol de ubicaciones (ciudad > región > país), un nivel por vuelta.
  const parents = new Map<number, number | null>();
  const isoOf = new Map<number, string | null>();
  let frontier = [...new Set(profiles.map((profile) => profile.location_id).filter((id): id is number => id !== null))];
  for (let level = 0; level < 3 && frontier.length > 0; level += 1) {
    for (const ids of chunksOf(frontier, CHUNK)) {
      const { data, error } = await client.from("locations").select("id, parent_id, iso_code").in("id", ids).limit(CHUNK);
      if (error) return fail("the locations", error.message);
      for (const row of data) {
        parents.set(row.id, row.parent_id);
        isoOf.set(row.id, row.iso_code);
      }
    }
    frontier = [...new Set([...parents.values()].filter((id): id is number => id !== null && !parents.has(id)))];
  }

  const countryNames = new Map<number, string>();
  const countryIds = [...new Set(profiles.map((profile) => countryIdOf(profile.location_id, parents)).filter((id): id is number => id !== null))];
  if (countryIds.length > 0) {
    const language = await client.from("languages").select("id").eq("code", CATALOG_LANGUAGE_CODE).maybeSingle();
    if (language.error || !language.data) return fail("the language", language.error?.message ?? "missing");
    for (const ids of chunksOf(countryIds, CHUNK)) {
      const { data, error } = await client.from("location_translations").select("location_id, name").eq("language_id", language.data.id).in("location_id", ids).limit(CHUNK);
      if (error) return fail("the country names", error.message);
      for (const row of data) countryNames.set(row.location_id, row.name);
    }
  }

  const rows: TherapistRow[] = [];
  for (const profile of profiles) {
    const countryId = countryIdOf(profile.location_id, parents);
    const statusId = latest.get(profile.id);
    const row = toTherapistRow({
      profile,
      person: people.get(profile.person_id),
      profileCode: profileCode.get(profile.status_id) ?? null,
      revisionCode: statusId === undefined ? null : (revisionCode.get(statusId) ?? null),
      countryIso: countryId === null ? null : (isoOf.get(countryId) ?? null),
      countryName: countryId === null ? null : (countryNames.get(countryId) ?? null),
      contacts: contacts.get(profile.id) ?? [],
      phoneTypeId,
      months,
      nowMs,
    });
    if (row) rows.push(row);
  }
  return { rows, complete };
}
