// Reads the public catalogs (therapies, locations) for the search form, with the PUBLIC client. The database already
// filters: anon only sees ACTIVE rows. Names come from the translation tables, in Spanish for now.
// Lee los catálogos públicos (terapias, ubicaciones) para el formulario de búsqueda, con el cliente PÚBLICO. La base ya
// filtra: anon solo ve filas ACTIVAS. Los nombres salen de las tablas de traducción, en español por ahora.
//
// Rules kept here / Reglas que se respetan acá:
//  - No nested joins under RLS: each table is read on its own and merged in code. / Sin joins anidados bajo RLS.
//  - Every read has an explicit limit below the 1,000-row cap of the API. / Toda lectura tiene un límite explícito.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";

type Client = SupabaseClient<Database>;

export const CATALOG_LANGUAGE_CODE = "es";
const MAX_ROWS = 1000;

export type CatalogOption = { id: number; name: string };

type Item = { id: number; code?: string | null };
type NameRow = { id: number; name: string };

// Therapies listed first, in this order, before the alphabetical rest. Owner decision 12/11/2026: the launch test is
// with LNT therapists. Empty this list to go back to a fully alphabetical list.
// Terapias que van primero, en este orden, antes del resto alfabético. Decisión del titular (12/11/2026): la prueba de
// lanzamiento es con terapeutas de LNT. Vaciar esta lista devuelve el orden totalmente alfabético.
export const THERAPIES_LISTED_FIRST: readonly string[] = ["lnt_schwiderski"];

// Pure: joins items with their names (fallback: the code, then the id) and sorts by name using Spanish rules,
// so "Ávila" sorts with the A's. Items whose code is in listFirst go first, in that order.
// Pura: une ítems con sus nombres (si falta: el código, luego el id) y ordena en español. Los ítems cuyo código está en
// listFirst van primero, en ese orden.
export function buildOptions(items: readonly Item[], names: readonly NameRow[], listFirst: readonly string[] = []): CatalogOption[] {
  const byId = new Map(names.map((row) => [row.id, row.name]));
  const rank = (item: Item): number => {
    const position = item.code ? listFirst.indexOf(item.code) : -1;
    return position === -1 ? listFirst.length : position;
  };
  return items
    .map((item) => ({ id: item.id, name: byId.get(item.id) ?? item.code ?? String(item.id), rank: rank(item) }))
    .sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name, CATALOG_LANGUAGE_CODE) || a.id - b.id)
    .map(({ id, name }) => ({ id, name }));
}

function fail(what: string, message: string): never {
  throw new Error(`Could not read ${what} / No se pudo leer ${what}: ${message}`);
}

async function getLanguageId(client: Client): Promise<number> {
  const { data, error } = await client
    .from("languages")
    .select("id")
    .eq("code", CATALOG_LANGUAGE_CODE)
    .limit(1);
  if (error) fail("languages / idiomas", error.message);
  const row = data?.[0];
  if (!row) fail("languages / idiomas", `language "${CATALOG_LANGUAGE_CODE}" not found / no existe`);
  return row.id;
}

// Active therapies, named and sorted. / Terapias activas, con nombre y ordenadas.
export async function listTherapies(client: Client): Promise<CatalogOption[]> {
  const languageId = await getLanguageId(client);

  const therapies = await client.from("therapies").select("id, code").limit(MAX_ROWS);
  if (therapies.error) fail("therapies / terapias", therapies.error.message);
  const items = therapies.data ?? [];
  if (items.length === 0) return [];

  const translations = await client
    .from("therapy_translations")
    .select("therapy_id, name")
    .eq("language_id", languageId)
    .in("therapy_id", items.map((item) => item.id))
    .limit(MAX_ROWS);
  if (translations.error) fail("therapy names / nombres de terapias", translations.error.message);

  return buildOptions(
    items,
    (translations.data ?? []).map((row) => ({ id: row.therapy_id, name: row.name })),
    THERAPIES_LISTED_FIRST,
  );
}

// Active locations one level down: parentId = null lists the countries; a country id lists its regions;
// a region id lists its cities. / Ubicaciones activas un nivel más abajo: null lista los países; un país, sus
// regiones; una región, sus ciudades.
export async function listLocations(client: Client, parentId: number | null): Promise<CatalogOption[]> {
  const languageId = await getLanguageId(client);

  const base = client.from("locations").select("id");
  const locations = await (parentId === null ? base.is("parent_id", null) : base.eq("parent_id", parentId)).limit(MAX_ROWS);
  if (locations.error) fail("locations / ubicaciones", locations.error.message);
  const items = locations.data ?? [];
  if (items.length === 0) return [];

  const translations = await client
    .from("location_translations")
    .select("location_id, name")
    .eq("language_id", languageId)
    .in("location_id", items.map((item) => item.id))
    .limit(MAX_ROWS);
  if (translations.error) fail("location names / nombres de ubicaciones", translations.error.message);

  return buildOptions(
    items,
    (translations.data ?? []).map((row) => ({ id: row.location_id, name: row.name })),
  );
}
