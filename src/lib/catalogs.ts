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

// ---------------------------------------------------------------------------------------------------------------------
// Catalogs for the therapist profile form / Catálogos para el formulario de perfil del terapeuta
// ---------------------------------------------------------------------------------------------------------------------

export type CodedOption = { id: number; code: string };
export type ChildOption = CatalogOption & { parentId: number };
export type LocationTree = { countries: CatalogOption[]; regions: ChildOption[]; cities: ChildOption[] };
export type CurrencyOption = { id: number; code: string; minorUnits: number };
export type FormCatalogs = {
  languages: CodedOption[];
  serviceModes: CodedOption[];
  sessionFormats: CodedOption[];
  contactTypes: CodedOption[];
  therapies: CatalogOption[];
  currencies: CurrencyOption[];
  rateAudiences: CodedOption[];
};

type CodedRow = { id: number; code: string };
const toCoded = (what: string, result: { data: CodedRow[] | null; error: { message: string } | null }): CodedOption[] => {
  if (result.error) fail(what, result.error.message);
  return (result.data ?? []).map((row) => ({ id: row.id, code: row.code }));
};

export async function listFormCatalogs(client: Client): Promise<FormCatalogs> {
  // One explicit query per table keeps the types exact (no table-name unions). / Una consulta explícita por tabla mantiene los tipos exactos.
  const [languages, serviceModes, sessionFormats, contactTypes, currencies, rateAudiences, therapies] = await Promise.all([
    client.from("languages").select("id, code").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    client.from("service_modes").select("id, code").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    client.from("session_formats").select("id, code").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    client.from("contact_types").select("id, code").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    client.from("currencies").select("id, code, minor_units").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    client.from("rate_audiences").select("id, code").eq("is_active", true).order("sort_order").limit(MAX_ROWS),
    listTherapies(client),
  ]);
  if (currencies.error) fail("currencies / monedas", currencies.error.message);
  return {
    languages: toCoded("languages / idiomas", languages),
    serviceModes: toCoded("service modes / modos de atención", serviceModes),
    sessionFormats: toCoded("session formats / formatos de sesión", sessionFormats),
    contactTypes: toCoded("contact types / tipos de contacto", contactTypes),
    therapies,
    currencies: (currencies.data ?? []).map((row) => ({ id: row.id, code: row.code, minorUnits: row.minor_units })),
    rateAudiences: toCoded("rate audiences / audiencias de tarifa", rateAudiences),
  };
}

// Pure: groups children under their parents, named and sorted. / Pura: agrupa hijos bajo sus padres, con nombre y ordenados.
export function buildChildOptions(items: readonly { id: number; parent_id: number | null }[], names: readonly NameRow[]): ChildOption[] {
  const parentById = new Map(items.map((item) => [item.id, item.parent_id]));
  return buildOptions(items, names)
    .map((option) => ({ ...option, parentId: parentById.get(option.id) ?? 0 }))
    .filter((option) => option.parentId !== 0);
}

// The whole country > region > city tree in a few calls (rows are read in pages below the 1,000-row cap of the API).
// Fine for the launch size (a few hundred rows); a world-wide catalog will need a search box instead.
// Todo el árbol país > región > ciudad en pocas llamadas (se lee por páginas bajo el tope de 1.000 filas de la API).
// Alcanza para el tamaño de lanzamiento (unos cientos de filas); un catálogo mundial necesitará un buscador.
export async function listLocationTree(client: Client): Promise<LocationTree> {
  const languageId = await getLanguageId(client);
  const levels = await client.from("location_levels").select("id, code").limit(50);
  if (levels.error) fail("location levels / niveles de ubicación", levels.error.message);
  const levelId = (code: string) => levels.data?.find((row) => row.code === code)?.id;

  const rows: { id: number; parent_id: number | null; level_id: number }[] = [];
  for (let from = 0; ; from += MAX_ROWS) {
    const page = await client.from("locations").select("id, parent_id, level_id").eq("is_active", true).order("id").range(from, from + MAX_ROWS - 1);
    if (page.error) fail("locations / ubicaciones", page.error.message);
    rows.push(...(page.data ?? []));
    if ((page.data?.length ?? 0) < MAX_ROWS) break;
  }

  const names: NameRow[] = [];
  const ids = rows.map((row) => row.id);
  for (let start = 0; start < ids.length; start += 200) {
    const chunk = ids.slice(start, start + 200);
    const translations = await client
      .from("location_translations")
      .select("location_id, name")
      .eq("language_id", languageId)
      .in("location_id", chunk)
      .limit(MAX_ROWS);
    if (translations.error) fail("location names / nombres de ubicaciones", translations.error.message);
    names.push(...(translations.data ?? []).map((row) => ({ id: row.location_id, name: row.name })));
  }

  const ofLevel = (code: string) => rows.filter((row) => row.level_id === levelId(code));
  return {
    countries: buildOptions(ofLevel("country"), names),
    regions: buildChildOptions(ofLevel("region"), names),
    cities: buildChildOptions(ofLevel("city"), names),
  };
}
