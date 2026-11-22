// Reads the follow-up lists with the ADMINISTRATOR's session (RLS applies; no service role). Several small queries, no nested joins.
// Lee las listas de seguimiento con la sesión del ADMINISTRADOR (rige RLS; sin service role). Varias consultas chicas, sin joins anidados.

import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { chunksOf, pickFollowUps, toFollowUpItem, type FollowUpItem, type RevisionStub } from "@/lib/admin/followup-view";

type Client = SupabaseClient<Database>;

const PAGE_SIZE = 1000; // the API returns at most 1,000 rows per request / la API devuelve como mucho 1.000 filas por pedido
const MAX_PAGES = 10;
const CHUNK = 40; // ids per request, so the address stays short / ids por pedido, para que la dirección no sea larga

const fail = (what: string, message: string): never => {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
};

export type FollowUpStubs = { rejected: RevisionStub[]; drafts: RevisionStub[]; complete: boolean };

// Light read of ALL revisions (no payload) to find each profile's latest one. / Lectura liviana de TODAS las revisiones (sin payload).
export async function loadFollowUpStubs(client: Client): Promise<FollowUpStubs> {
  const statuses = await client.from("revision_statuses").select("id, code").in("code", ["rejected", "draft"]).limit(10);
  if (statuses.error) return fail("the revision statuses", statuses.error.message);
  const rejected = statuses.data.find((row) => row.code === "rejected");
  const draft = statuses.data.find((row) => row.code === "draft");
  if (!rejected || !draft) return fail("the revision statuses", "rejected or draft is missing");

  const rows: RevisionStub[] = [];
  let complete = false;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data, error } = await client
      .from("profile_revisions")
      .select("id, profile_id, status_id, created_at, decided_at, rejection_reason")
      .order("created_at", { ascending: false })
      .order("id", { ascending: true })
      .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    if (error) return fail("the revisions", error.message);
    rows.push(...data);
    if (data.length < PAGE_SIZE) {
      complete = true;
      break;
    }
  }
  return { ...pickFollowUps(rows, { rejected: rejected.id, draft: draft.id }), complete };
}

export async function loadFollowUpItems(client: Client, stubs: FollowUpStubs): Promise<{ rejected: FollowUpItem[]; drafts: FollowUpItem[] }> {
  const nowMs = Date.now();
  const all = [...stubs.rejected, ...stubs.drafts];
  if (all.length === 0) return { rejected: [], drafts: [] };

  const payloads = new Map<string, unknown>();
  for (const ids of chunksOf(all.map((stub) => stub.id), CHUNK)) {
    const { data, error } = await client.from("profile_revisions").select("id, payload").in("id", ids).limit(CHUNK);
    if (error) return fail("the revision contents", error.message);
    for (const row of data) payloads.set(row.id, row.payload);
  }

  const profiles = new Map<string, { person_id: string; display_name: string | null; status_id: number }>();
  for (const ids of chunksOf([...new Set(all.map((stub) => stub.profile_id))], CHUNK)) {
    const { data, error } = await client.from("therapist_profiles").select("id, person_id, display_name, status_id").in("id", ids).limit(CHUNK);
    if (error) return fail("the profiles", error.message);
    for (const row of data) profiles.set(row.id, row);
  }

  const people = new Map<string, { full_name: string | null; email: string | null; erased_at: string | null }>();
  for (const ids of chunksOf([...new Set([...profiles.values()].map((profile) => profile.person_id))], CHUNK)) {
    const { data, error } = await client.from("people").select("id, full_name, email, erased_at").in("id", ids).limit(CHUNK);
    if (error) return fail("the people", error.message);
    for (const row of data) people.set(row.id, row);
  }

  const profileStatuses = await client.from("profile_statuses").select("id, code").limit(50);
  if (profileStatuses.error) return fail("the profile statuses", profileStatuses.error.message);
  const statusCode = new Map(profileStatuses.data.map((row) => [row.id, row.code]));

  const contactTypes = await client.from("contact_types").select("id, code").limit(50);
  if (contactTypes.error) return fail("the contact types", contactTypes.error.message);
  const contactTypeCodes = new Map(contactTypes.data.map((row) => [row.id, row.code]));

  const build = (stub: RevisionStub, kind: "rejected" | "draft"): FollowUpItem | null => {
    const profile = profiles.get(stub.profile_id);
    const person = profile ? people.get(profile.person_id) : undefined;
    if (!profile || !person || person.erased_at !== null) return null; // erased people are not contacted / a quien se dio de baja no se lo contacta
    return toFollowUpItem({
      stub, kind, nowMs, contactTypeCodes,
      payload: payloads.get(stub.id),
      profileDisplayName: profile.display_name,
      personName: person.full_name,
      email: person.email,
      profileStatusCode: statusCode.get(profile.status_id) ?? null,
    });
  };
  const keep = (item: FollowUpItem | null): item is FollowUpItem => item !== null;
  return {
    rejected: stubs.rejected.map((stub) => build(stub, "rejected")).filter(keep),
    drafts: stubs.drafts.map((stub) => build(stub, "draft")).filter(keep),
  };
}
