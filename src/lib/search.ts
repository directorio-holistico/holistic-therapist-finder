// Search through the database function search_profiles (the database decides who is visible and in which group) and
// records unmet demand with log_search. Result rows are turned into plain cards for the page.
// Búsqueda con la función de base search_profiles (la base decide quién se ve y en qué grupo) y registro de demanda no
// cubierta con log_search. Las filas de resultado se convierten en tarjetas simples para la página.

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";
import { PAGE_SIZE, type ServiceModeCode } from "@/lib/search-query";

type Client = SupabaseClient<Database>;

export type RateFrom = { audience: string; amount: number; currency: string };

export type SearchCard = {
  profileId: string;
  group: number;
  displayName: string;
  headline: string | null;
  place: string;
  therapies: string[];
  serviceModes: string[];
  sessionFormats: string[];
  languages: string[];
  rates: RateFrom[];
  ratesConfirmedAt: string | null;
  ratesCurrent: boolean;
  isPinned: boolean;
};

export type SearchPage = { cards: SearchCard[]; total: number };

// Only the columns the page uses; the real row type from the database is assignable to this.
// Solo las columnas que usa la página; el tipo real de la fila de la base es asignable a este.
export type SearchRow = {
  result_group?: number | null;
  total_count?: number | null;
  profile_id?: string | null;
  display_name?: string | null;
  headline?: string | null;
  city_name?: string | null;
  region_name?: string | null;
  country_name?: string | null;
  therapy_ids?: number[] | null;
  therapy_names?: string[] | null;
  service_modes?: string[] | null;
  session_formats?: string[] | null;
  languages?: string[] | null;
  rates_from?: unknown;
  rates_confirmed_at?: string | null;
  rates_current?: boolean | null;
  is_pinned?: boolean | null;
};

const ratesFromSchema = z.record(
  z.string(),
  z.object({ amount: z.coerce.number().finite(), currency: z.string().min(1).max(8) }),
);

// jsonb { audience: { amount, currency } } -> list, in the order own_country first. Anything odd gives an empty list.
// jsonb { audiencia: { monto, moneda } } -> lista, con own_country primero. Cualquier rareza da una lista vacía.
export function parseRatesFrom(value: unknown): RateFrom[] {
  const parsed = ratesFromSchema.safeParse(value);
  if (!parsed.success) return [];
  return Object.entries(parsed.data)
    .map(([audience, { amount, currency }]) => ({ audience, amount, currency }))
    .sort((a, b) => (a.audience === "own_country" ? -1 : b.audience === "own_country" ? 1 : a.audience.localeCompare(b.audience)));
}

// Therapies of a card: alphabetical (Spanish), but the therapy the visitor searched for goes first (A, B, C searching B -> B, A, C).
// ids and names come aligned from the database (both ordered by id). If they are not aligned, names are kept alphabetical.
// Terapias de una tarjeta: alfabético (español), pero la terapia buscada va primera (A, B, C buscando B -> B, A, C).
// Los ids y los nombres vienen alineados de la base (ambos ordenados por id). Si no lo están, queda el orden alfabético.
export function orderTherapies(
  ids: readonly number[] | null | undefined,
  names: readonly string[] | null | undefined,
  searchedId: number | null = null,
): string[] {
  const list = names ?? [];
  const aligned = ids != null && ids.length === list.length;
  const items = list.map((name, index) => ({ name, id: aligned ? (ids[index] ?? null) : null }));
  items.sort((a, b) => a.name.localeCompare(b.name, "es"));
  const first = searchedId === null ? -1 : items.findIndex((item) => item.id === searchedId);
  if (first > 0) items.unshift(...items.splice(first, 1));
  return items.map((item) => item.name);
}

export function toCard(row: SearchRow, searchedTherapyId: number | null = null): SearchCard | null {
  if (!row.profile_id || !row.display_name) return null;
  const place = [row.city_name, row.region_name, row.country_name].filter((part): part is string => Boolean(part)).join(", ");
  return {
    profileId: row.profile_id,
    group: row.result_group ?? 1,
    displayName: row.display_name,
    headline: row.headline ?? null,
    place,
    therapies: orderTherapies(row.therapy_ids, row.therapy_names, searchedTherapyId),
    serviceModes: row.service_modes ?? [],
    sessionFormats: row.session_formats ?? [],
    languages: row.languages ?? [],
    rates: parseRatesFrom(row.rates_from),
    ratesConfirmedAt: row.rates_confirmed_at ?? null,
    ratesCurrent: row.rates_current === true,
    isPinned: row.is_pinned === true,
  };
}

export function splitByGroup(cards: readonly SearchCard[]): { group: number; cards: SearchCard[] }[] {
  const groups: { group: number; cards: SearchCard[] }[] = [];
  for (const card of cards) {
    const last = groups[groups.length - 1];
    if (last && last.group === card.group) last.cards.push(card);
    else groups.push({ group: card.group, cards: [card] });
  }
  return groups;
}

// therapyId / locationId null = "Todos" (any therapy / anywhere). The database accepts both as optional.
// therapyId / locationId null = "Todos" (cualquier terapia / cualquier lugar). La base acepta ambos como opcionales.
export type SearchInput = { therapyId: number | null; locationId: number | null; serviceMode: ServiceModeCode | null; page: number };

// Unmet demand is only recorded for a search with a specific therapy AND a specific place.
// La demanda no cubierta solo se registra con una terapia Y un lugar concretos.
export type UnmetSearchInput = { therapyId: number; locationId: number; serviceMode: ServiceModeCode | null };

export async function searchProfiles(client: Client, input: SearchInput): Promise<SearchPage> {
  const { data, error } = await client.rpc("search_profiles", {
    p_therapy_id: input.therapyId ?? undefined,
    p_location_id: input.locationId ?? undefined,
    p_service_mode: input.serviceMode ?? undefined,
    p_limit: PAGE_SIZE,
    p_offset: (input.page - 1) * PAGE_SIZE,
  });
  if (error) throw new Error(`Search failed / La búsqueda falló: ${error.message}`);
  const rows: SearchRow[] = data ?? [];
  const cards = rows.map((row) => toCard(row, input.therapyId)).filter((card): card is SearchCard => card !== null);
  const total = rows.length > 0 ? Number(rows[0]?.total_count ?? rows.length) : 0;
  return { cards, total };
}

// Best effort: the database counts the search only if it truly has no result. A failure here never breaks the page.
// Mejor esfuerzo: la base cuenta la búsqueda solo si de verdad no tiene resultado. Un fallo acá nunca rompe la página.
export async function logUnmetSearch(client: Client, input: UnmetSearchInput): Promise<void> {
  try {
    await client.rpc("log_search", {
      p_therapy_id: input.therapyId,
      p_location_id: input.locationId,
      p_service_mode: input.serviceMode ?? undefined,
    });
  } catch {
    // intentionally ignored / ignorado a propósito
  }
}
