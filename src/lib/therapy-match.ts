// Finds a therapy of the catalog by the name a person typed: same name ignoring accents, capitals and extra spaces (never a partial match).
// Used so nobody asks for a therapy that is already in the list. / Se usa para que nadie pida una terapia que ya está en la lista.
// Busca una terapia del catálogo por el nombre que escribió una persona: mismo nombre sin importar tildes, mayúsculas ni espacios de más (nunca parcial).

import type { CatalogOption } from "@/lib/catalogs";
import { normalizeText } from "@/lib/option-filter";

const squash = (value: string): string => normalizeText(value).replace(/\s+/g, " ").trim();

export function findExistingTherapy(options: readonly CatalogOption[], typed: string): CatalogOption | null {
  const wanted = squash(typed);
  if (wanted === "") return null;
  return options.find((option) => squash(option.name) === wanted) ?? null;
}
