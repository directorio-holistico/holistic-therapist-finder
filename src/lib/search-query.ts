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
  cityId: number | null;
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

// The form has one checkbox per mode, both checked by default. Both checked (or none, or only invalid values) means "no filter";
// exactly one valid mode means that mode.
// El formulario tiene una casilla por modo, las dos tildadas por defecto. Las dos (o ninguna, o solo valores inválidos) significan
// "sin filtro"; exactamente un modo válido significa ese modo.
function modeOf(value: string | string[] | undefined): ServiceModeCode | null {
  const values = Array.isArray(value) ? value.slice(0, 10) : [value];
  const found = new Set<ServiceModeCode>();
  for (const item of values) {
    const parsed = modeSchema.safeParse(item?.trim());
    if (parsed.success) found.add(parsed.data);
  }
  return found.size === 1 ? ([...found][0] ?? null) : null;
}

export function parseSearchQuery(raw: RawParams): SearchQuery {
  const page = pageSchema.safeParse(first(raw.page)?.trim());
  return {
    therapyId: optionalId(raw.therapy),
    countryId: optionalId(raw.country),
    regionId: optionalId(raw.region),
    cityId: optionalId(raw.city),
    serviceMode: modeOf(raw.mode),
    page: page.success ? page.data : 1,
  };
}

// The most specific place chosen (city, else region, else country). / El lugar más específico elegido (ciudad, si no región, si no país).
export function locationIdOf(query: SearchQuery): number | null {
  return query.cityId ?? query.regionId ?? query.countryId;
}

export function buildSearchHref(query: SearchQuery, page: number): string {
  const params = new URLSearchParams();
  if (query.therapyId !== null) params.set("therapy", String(query.therapyId));
  if (query.countryId !== null) params.set("country", String(query.countryId));
  if (query.regionId !== null) params.set("region", String(query.regionId));
  if (query.cityId !== null) params.set("city", String(query.cityId));
  if (query.serviceMode !== null) params.set("mode", query.serviceMode);
  if (page > 1) params.set("page", String(page));
  const text = params.toString();
  return text ? `/buscar?${text}` : "/buscar";
}

// Address for the form values when a filter changes (the form updates the search by itself). Empty values are dropped, the page
// restarts, and changing a place level clears the levels below it (a new country has other regions, a new region other cities).
// Dirección a partir de los valores del formulario cuando cambia un filtro (el formulario actualiza la búsqueda solo). Se descartan
// los vacíos, la página vuelve a 1 y cambiar un nivel del lugar borra los niveles de abajo (otro país tiene otras regiones, etc.).
export function hrefFromFormValues(entries: Iterable<[string, unknown]>, changedField: string): string {
  const allowed = new Set(["therapy", "country", "region", "city", "mode"]);
  const params = new URLSearchParams();
  // Two checkboxes send "mode" twice: both (or none) means no filter, one means that mode. / Dos casillas envían "mode" dos veces: las dos (o ninguna) = sin filtro, una = ese modo.
  const modes = new Set<ServiceModeCode>();
  for (const [name, value] of entries) {
    if (name === "mode") {
      const parsed = modeSchema.safeParse(typeof value === "string" ? value.trim() : undefined);
      if (parsed.success) modes.add(parsed.data);
    } else if (allowed.has(name) && typeof value === "string" && value.trim() !== "") {
      params.set(name, value.trim());
    }
  }
  const onlyMode = modes.size === 1 ? [...modes][0] : undefined;
  if (onlyMode) params.set("mode", onlyMode);
  if (changedField === "country") {
    params.delete("region");
    params.delete("city");
  }
  if (changedField === "region") params.delete("city");
  const text = params.toString();
  return text ? `/buscar?${text}` : "/buscar";
}
