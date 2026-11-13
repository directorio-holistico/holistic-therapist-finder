// Names for the ids found inside a revision payload, and the readable path of a city. Read with the administrator's session.
// Nombres para los ids que aparecen dentro del payload de una revisión, y la ruta legible de una ciudad. Con la sesión del admin.

import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CATALOG_LANGUAGE_CODE, listFormCatalogs } from "@/lib/catalogs";
import { labelLanguage, labelRateAudience, labelServiceMode, labelSessionFormat } from "@/lib/labels";
import type { ViewLookups } from "@/lib/admin/revision-view";
import type { Database } from "@/lib/supabase/database.types";

type Client = SupabaseClient<Database>;

export async function loadViewLookups(client: Client): Promise<ViewLookups> {
  const catalogs = await listFormCatalogs(client);
  const codes = (rows: { id: number; code: string }[], label: (code: string) => string) => new Map(rows.map((row) => [row.id, label(row.code)]));
  return {
    therapies: new Map(catalogs.therapies.map((therapy) => [therapy.id, therapy.name])),
    currencies: new Map(catalogs.currencies.map((currency) => [currency.id, currency.code])),
    audiences: codes(catalogs.rateAudiences, labelRateAudience),
    languages: codes(catalogs.languages, labelLanguage),
    serviceModes: codes(catalogs.serviceModes, labelServiceMode),
    sessionFormats: codes(catalogs.sessionFormats, labelSessionFormat),
    contactTypes: new Map(catalogs.contactTypes.map((type) => [type.id, type.code])),
  };
}

// "Cinco Saltos, Río Negro, Argentina" for a city id (city > region > country), or null when it cannot be read.
// "Cinco Saltos, Río Negro, Argentina" para el id de una ciudad (ciudad > región > país), o null si no se puede leer.
export async function locationPath(client: Client, locationId: number): Promise<string | null> {
  const chain: number[] = [];
  let current: number | null = locationId;
  for (let level = 0; level < 3 && current !== null; level += 1) {
    chain.push(current);
    const { data, error }: { data: { parent_id: number | null } | null; error: { message: string } | null } = await client
      .from("locations").select("parent_id").eq("id", current).maybeSingle();
    if (error || !data) return null;
    current = data.parent_id;
  }
  const language = await client.from("languages").select("id").eq("code", CATALOG_LANGUAGE_CODE).maybeSingle();
  if (language.error || !language.data) return null;
  const names = await client.from("location_translations").select("location_id, name").eq("language_id", language.data.id).in("location_id", chain).limit(10);
  if (names.error) return null;
  const byId = new Map((names.data ?? []).map((row) => [row.location_id, row.name]));
  return chain.map((id) => byId.get(id) ?? `#${id}`).join(", ");
}
