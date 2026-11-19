// Type-ahead filter for long option lists (therapies). Pure code, no database, no React.
// Filtro por escritura para listas largas de opciones (terapias). Código puro, sin base y sin React.
//
// Rule / Regla: with fewer than MIN_FILTER_CHARS letters typed, EVERYTHING is shown. From there on, an option matches when
// EVERY word typed is the beginning of some word of its name (any order, no accents, no capitals):
// "mas cal" finds "Masaje con calor y elementos". The catalog order is kept (it is not re-ranked).
// Con menos de MIN_FILTER_CHARS letras se muestra TODO. Desde ahí, una opción coincide cuando CADA palabra escrita es el
// comienzo de alguna palabra de su nombre (en cualquier orden, sin tildes, sin mayúsculas). Se mantiene el orden del catálogo.

export const MIN_FILTER_CHARS = 3;

export function normalizeText(value: string): string {
  return value.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase("es");
}

const wordsOf = (value: string): string[] => normalizeText(value).split(/[^\p{L}\p{N}]+/u).filter(Boolean);

// True when the typed text is long enough to filter (spaces at the ends do not count).
// Verdadero cuando el texto escrito alcanza para filtrar (los espacios de los extremos no cuentan).
export function isFiltering(query: string): boolean {
  return normalizeText(query).trim().length >= MIN_FILTER_CHARS;
}

export function filterOptions<T extends { name: string }>(options: readonly T[], query: string): T[] {
  if (!isFiltering(query)) return [...options];
  const typed = wordsOf(query);
  if (typed.length === 0) return [...options];
  return options.filter((option) => {
    const words = wordsOf(option.name);
    return typed.every((token) => words.some((word) => word.startsWith(token)));
  });
}
