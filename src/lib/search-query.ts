// Reads the search form from the URL. Anything invalid is ignored (never an error page): the URL is user input.
// Lee el formulario de búsqueda desde la URL. Lo inválido se ignora (nunca una página de error): la URL es entrada del usuario.

import { z } from "zod";

export const PAGE_SIZE = 20;
// The database accepts offsets up to 10,000. / La base acepta desplazamientos hasta 10.000.
export const MAX_PAGE = 10000 / PAGE_SIZE;

export type ServiceModeCode = "in_person" | "remote";

export type SearchQuery = {
  therapyId: number | null;
  countryId: number | null;
  regionId: number | null;
  serviceMode: ServiceModeCode | null;
  page: number;
};

type RawParams = Record<string, string | string[] | undefined>;

const idSchema = z.coerce.number().int().positive().max(2147483647);
const modeSchema = z.enum(["in_person", "remote"]);
const pageSchema = z.coerce.number().int().min(1).max(MAX_PAGE);

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function optionalId(value: string | string[] | undefined): number | null {
  const text = first(value)?.trim();
  if (!text) return null;
  const parsed = idSchema.safeParse(text);
  return parsed.success ? parsed.data : null;
}

export function parseSearchQuery(raw: RawParams): SearchQuery {
  const mode = modeSchema.safeParse(first(raw.mode)?.trim());
  const page = pageSchema.safeParse(first(raw.page)?.trim());
  return {
    therapyId: optionalId(raw.therapy),
    countryId: optionalId(raw.country),
    regionId: optionalId(raw.region),
    serviceMode: mode.success ? mode.data : null,
    page: page.success ? page.data : 1,
  };
}

// The most specific place chosen. / El lugar más específico elegido.
export function locationIdOf(query: SearchQuery): number | null {
  return query.regionId ?? query.countryId;
}

export function buildSearchHref(query: SearchQuery, page: number): string {
  const params = new URLSearchParams();
  if (query.therapyId !== null) params.set("therapy", String(query.therapyId));
  if (query.countryId !== null) params.set("country", String(query.countryId));
  if (query.regionId !== null) params.set("region", String(query.regionId));
  if (query.serviceMode !== null) params.set("mode", query.serviceMode);
  if (page > 1) params.set("page", String(page));
  const text = params.toString();
  return text ? `/buscar?${text}` : "/buscar";
}
