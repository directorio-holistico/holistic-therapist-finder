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
  latestRevisions,
  stateOf,
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

// Independent reads run at the same time (each one waiting for the previous made the page take seconds). / Las lecturas independientes
// corren a la vez (esperar cada una a la anterior hacía tardar la página varios segundos).
async function readPaged<T>(read: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>, what: string): Promise<{ items: T[]; complete: boolean }> {
  const items: T[] = [];
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data, error } = await read(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    if (error || !data) return fail(what, error?.message ?? "no data");
    items.push(...data);
    if (data.length < PAGE_SIZE) return { items, complete: true };
  }
  return { items, complete: false };
}

export async function loadTherapistList(client: Client): Promise<TherapistList> {
  const nowMs = Date.now();

  // Round 1: everything that does not depend on anything else. / Vuelta 1: todo lo que no depende de nada.
  const [profileStatuses, revisionStatuses, contactTypes, validity, language, profilesRead, revisionsRead] = await Promise.all([
    client.from("profile_statuses").select("id, code").limit(50),
    client.from("revision_statuses").select("id, code").limit(50),
    client.from("contact_types").select("id, code").limit(50),
    client.rpc("rates_validity_months"),
    client.from("languages").select("id").eq("code", CATALOG_LANGUAGE_CODE).maybeSingle(),
    readPaged<ProfileStub>(
      (from, to) =>
        client
          .from("therapist_profiles")
          .select("id, person_id, display_name, status_id, location_id, rates_confirmed_at, approved_at")
          .order("created_at", { ascending: true })
          .order("id", { ascending: true })
          .range(from, to),
      "the profiles",
    ),
    // Light read of ALL revisions (no payload) to know each profile's latest one. / Lectura liviana de TODAS las revisiones (sin payload).
    readPaged<RevisionLite>(
      (from, to) =>
        client
          .from("profile_revisions")
          .select("id, profile_id, status_id, created_at")
          .order("created_at", { ascending: false })
          .order("id", { ascending: true })
          .range(from, to),
      "the revisions",
    ),
  ]);
  if (profileStatuses.error) return fail("the profile statuses", profileStatuses.error.message);
  if (revisionStatuses.error) return fail("the revision statuses", revisionStatuses.error.message);
  if (contactTypes.error) return fail("the contact types", contactTypes.error.message);
  if (validity.error || typeof validity.data !== "number") return fail("the rates validity setting", validity.error?.message ?? "not a number");
  if (language.error || !language.data) return fail("the language", language.error?.message ?? "missing");

  const profileCode = new Map(profileStatuses.data.map((row) => [row.id, row.code]));
  const revisionCode = new Map(revisionStatuses.data.map((row) => [row.id, row.code]));
  const discardedId = revisionStatuses.data.find((row) => row.code === "discarded")?.id ?? null;
  const phoneTypeId = contactTypes.data.find((row) => row.code === "phone")?.id ?? null;
  const contactTypeCodes = new Map(contactTypes.data.map((row) => [row.id, row.code]));
  const months = validity.data as number;
  const languageId = language.data.id;
  const profiles = profilesRead.items;
  const complete = profilesRead.complete && revisionsRead.complete;
  const latest = latestRevisions(revisionsRead.items, discardedId);

  // Pending, rejected and draft profiles keep their phone in the latest revision (the live contacts are still empty).
  // Los perfiles en espera, rechazados y borradores guardan su teléfono en la última revisión (los contactos vigentes siguen vacíos).
  const payloadIds: string[] = [];
  for (const profile of profiles) {
    const last = latest.get(profile.id);
    if (!last) continue;
    const decided = stateOf(profileCode.get(profile.status_id) ?? null, revisionCode.get(last.status_id) ?? null);
    if (decided && (decided.state === "pending" || decided.state === "rejected" || decided.state === "draft")) payloadIds.push(last.id);
  }

  const people = new Map<string, PersonStub>();
  const contacts = new Map<string, ContactStub[]>();
  const payloads = new Map<string, unknown>();
  const parents = new Map<number, number | null>();
  const isoOf = new Map<number, string | null>();

  // Round 2: what depends on the profiles; the chunks of each read also go together. / Vuelta 2: lo que depende de los perfiles; los
  // pedazos de cada lectura también van juntos.
  const readPeople = Promise.all(
    chunksOf([...new Set(profiles.map((profile) => profile.person_id))], CHUNK).map(async (ids) => {
      const { data, error } = await client.from("people").select("id, full_name, email, created_at, erased_at").in("id", ids).limit(CHUNK);
      if (error) return fail("the people", error.message);
      for (const row of data) people.set(row.id, row);
    }),
  );
  const readContacts = Promise.all(
    (phoneTypeId === null ? [] : chunksOf(profiles.map((profile) => profile.id), CHUNK)).map(async (ids) => {
      const { data, error } = await client
        .from("profile_contacts")
        .select("profile_id, contact_type_id, value, accepts_whatsapp")
        .eq("contact_type_id", phoneTypeId as number)
        .in("profile_id", ids)
        .limit(CHUNK * 10);
      if (error) return fail("the contacts", error.message);
      for (const row of data) contacts.set(row.profile_id, [...(contacts.get(row.profile_id) ?? []), row]);
    }),
  );
  const readPayloads = Promise.all(
    chunksOf(payloadIds, CHUNK).map(async (ids) => {
      const { data, error } = await client.from("profile_revisions").select("id, payload").in("id", ids).limit(CHUNK);
      if (error) return fail("the revision contents", error.message);
      for (const row of data) payloads.set(row.id, row.payload);
    }),
  );
  // Country of each profile: walk the location tree upwards (city > region > country), one level per round (each level needs the last).
  // País de cada perfil: se sube por el árbol de ubicaciones (ciudad > región > país), un nivel por vuelta (cada nivel necesita el anterior).
  const readLocations = (async () => {
    let frontier = [...new Set(profiles.map((profile) => profile.location_id).filter((id): id is number => id !== null))];
    for (let level = 0; level < 3 && frontier.length > 0; level += 1) {
      await Promise.all(
        chunksOf(frontier, CHUNK).map(async (ids) => {
          const { data, error } = await client.from("locations").select("id, parent_id, iso_code").in("id", ids).limit(CHUNK);
          if (error) return fail("the locations", error.message);
          for (const row of data) {
            parents.set(row.id, row.parent_id);
            isoOf.set(row.id, row.iso_code);
          }
        }),
      );
      frontier = [...new Set([...parents.values()].filter((id): id is number => id !== null && !parents.has(id)))];
    }
  })();
  await Promise.all([readPeople, readContacts, readPayloads, readLocations]);

  // Round 3: the country names (they need the countries found above). / Vuelta 3: los nombres de país (necesitan los países hallados).
  const countryNames = new Map<number, string>();
  const countryIds = [...new Set(profiles.map((profile) => countryIdOf(profile.location_id, parents)).filter((id): id is number => id !== null))];
  await Promise.all(
    chunksOf(countryIds, CHUNK).map(async (ids) => {
      const { data, error } = await client.from("location_translations").select("location_id, name").eq("language_id", languageId).in("location_id", ids).limit(CHUNK);
      if (error) return fail("the country names", error.message);
      for (const row of data) countryNames.set(row.location_id, row.name);
    }),
  );

  const rows: TherapistRow[] = [];
  for (const profile of profiles) {
    const countryId = countryIdOf(profile.location_id, parents);
    const lastRevision = latest.get(profile.id);
    const row = toTherapistRow({
      profile,
      person: people.get(profile.person_id),
      profileCode: profileCode.get(profile.status_id) ?? null,
      revisionCode: lastRevision === undefined ? null : (revisionCode.get(lastRevision.status_id) ?? null),
      countryIso: countryId === null ? null : (isoOf.get(countryId) ?? null),
      countryName: countryId === null ? null : (countryNames.get(countryId) ?? null),
      contacts: contacts.get(profile.id) ?? [],
      phoneTypeId,
      months,
      nowMs,
      revisionPayload: lastRevision === undefined ? undefined : payloads.get(lastRevision.id),
      contactTypeCodes,
    });
    if (row) rows.push(row);
  }
  return { rows, complete };
}
