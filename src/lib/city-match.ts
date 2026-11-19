// Finds a city of the catalog by the name a person typed: same name ignoring accents, capitals and extra spaces (never a partial match).
// Busca una ciudad del catálogo por el nombre que escribió una persona: mismo nombre sin importar tildes, mayúsculas ni espacios de más (nunca parcial).

import type { CatalogOption } from "@/lib/catalogs";
import { normalizeText } from "@/lib/option-filter";

const squash = (value: string): string => normalizeText(value).replace(/\s+/g, " ").trim();

export function findExistingCity(options: readonly CatalogOption[], typed: string): CatalogOption | null {
  const wanted = squash(typed);
  if (wanted === "") return null;
  const found = options.filter((option) => squash(option.name) === wanted);
  return found.length === 1 ? (found[0] ?? null) : null; // two cities with the same name: not guessed / dos ciudades con el mismo nombre: no se adivina
}
