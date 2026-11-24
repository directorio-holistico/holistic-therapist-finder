// Reads what the therapy screen shows, with the ADMINISTRATOR's session (RLS applies; no service role): the whole catalog (also the hidden
// therapies), how many profiles hold each one, and the therapies that therapists asked for. Several small queries, no nested joins.
// Lee lo que muestra la pantalla de terapias, con la sesión del ADMINISTRADOR (rige RLS; sin service role): todo el catálogo (también las
// ocultas), cuántos perfiles tiene cada una y las terapias que pidieron los terapeutas. Varias consultas chicas, sin joins anidados.

import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CATALOG_LANGUAGE_CODE } from "@/lib/catalogs";
import { SUGGESTIONS_SHOWN } from "@/lib/admin/therapy-admin";
import type { Database } from "@/lib/supabase/database.types";

type Client = SupabaseClient<Database>;

const PAGE_SIZE = 1000; // the API returns at most 1,000 rows per request / la API devuelve como mucho 1.000 filas por pedido
const MAX_PAGES = 10;

export type TherapyRow = {
  id: number;
  code: string;
  name: string;
  shortName: string | null;
  sortOrder: number;
  isActive: boolean;
  profiles: number;
};

export type SuggestionRow = {
  revisionId: string;
  profileName: string;
  text: string;
  statusCode: string;
  at: string | null;
};

const fail = (what: string, message: string): never => {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
};

async function countProfilesByTherapy(client: Client): Promise<Map<number, number>> {
  const counts = new Map<number, number>();
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { data, error } = await client
      .from("profile_therapies")
      .select("profile_id, therapy_id")
      .order("profile_id", { ascending: true })
      .order("therapy_id", { ascending: true })
      .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    if (error) return fail("the therapies of the profiles", error.message);
    for (const row of data) counts.set(row.therapy_id, (counts.get(row.therapy_id) ?? 0) + 1);
    if (data.length < PAGE_SIZE) break;
  }
  return counts;
}

export async function loadTherapyCatalog(client: Client): Promise<TherapyRow[]> {
  const language = await client.from("languages").select("id").eq("code", CATALOG_LANGUAGE_CODE).maybeSingle();
  if (language.error || !language.data) return fail("the catalog language", language.error?.message ?? "missing");
  const [therapies, translations, counts] = await Promise.all([
    client.from("therapies").select("id, code, sort_order, is_active").order("sort_order", { ascending: true }).order("id", { ascending: true }).limit(PAGE_SIZE),
    client.from("therapy_translations").select("therapy_id, name, short_name").eq("language_id", language.data.id).limit(PAGE_SIZE),
    countProfilesByTherapy(client),
  ]);
  if (therapies.error) return fail("the therapies", therapies.error.message);
  if (translations.error) return fail("the therapy names", translations.error.message);
  const names = new Map(translations.data.map((row) => [row.therapy_id, row]));
  return therapies.data.map((row) => ({
    id: row.id,
    code: row.code,
    name: names.get(row.id)?.name ?? row.code,
    shortName: names.get(row.id)?.short_name ?? null,
    sortOrder: row.sort_order,
    isActive: row.is_active,
    profiles: counts.get(row.id) ?? 0,
  }));
}

export async function loadSuggestions(client: Client): Promise<SuggestionRow[]> {
  const [revisions, statuses] = await Promise.all([
    client
      .from("profile_revisions")
      .select("id, profile_id, status_id, suggested_therapy, created_at, decided_at")
      .not("suggested_therapy", "is", null)
      .order("created_at", { ascending: false })
      .limit(SUGGESTIONS_SHOWN),
    client.from("revision_statuses").select("id, code").limit(20),
  ]);
  if (revisions.error) return fail("the suggested therapies", revisions.error.message);
  if (statuses.error) return fail("the revision statuses", statuses.error.message);
  const statusCode = new Map(statuses.data.map((row) => [row.id, row.code]));

  const profileIds = [...new Set(revisions.data.map((row) => row.profile_id))];
  const profiles = profileIds.length === 0
    ? { data: [], error: null }
    : await client.from("therapist_profiles").select("id, display_name").in("id", profileIds).limit(SUGGESTIONS_SHOWN);
  if (profiles.error) return fail("the profiles", profiles.error.message);
  const nameOf = new Map((profiles.data ?? []).map((row) => [row.id, row.display_name]));

  return revisions.data.flatMap((row) => {
    const text = row.suggested_therapy?.trim() ?? "";
    if (text === "") return [];
    return [{
      revisionId: row.id,
      profileName: nameOf.get(row.profile_id) ?? "Perfil sin nombre",
      text,
      statusCode: statusCode.get(row.status_id) ?? "?",
      at: row.decided_at ?? row.created_at,
    }];
  });
}
