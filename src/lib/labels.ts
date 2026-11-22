// Spanish labels for catalog codes that have no translation table yet (service modes, formats, audiences, languages).
// Unknown codes are shown as they are, so a new catalog row never breaks the page.
// Etiquetas en español para códigos de catálogo sin tabla de traducción todavía. Un código desconocido se muestra tal cual,
// así una fila nueva del catálogo no rompe la página.

const SERVICE_MODES: Record<string, string> = { in_person: "Presencial", remote: "A distancia" };
const SESSION_FORMATS: Record<string, string> = { individual: "Individual", group: "Grupal" };
const RATE_AUDIENCES: Record<string, string> = {
  own_country: "Residentes en el país del terapeuta",
  other_countries: "Desde otros países",
};
const LANGUAGES: Record<string, string> = {
  es: "Español", en: "Inglés", pt: "Portugués", fr: "Francés", it: "Italiano", de: "Alemán",
};

export const labelServiceMode = (code: string): string => SERVICE_MODES[code] ?? code;
export const labelSessionFormat = (code: string): string => SESSION_FORMATS[code] ?? code;
export const labelRateAudience = (code: string): string => RATE_AUDIENCES[code] ?? code;
// The public profile names the therapist's country ("Residentes en Argentina"): shorter and clearer than "en el país del
// terapeuta". Without a country name it falls back to a short generic text. The editor and the admin keep the long label above.
// El perfil público nombra el país del terapeuta ("Residentes en Argentina"): más corto y claro que "en el país del terapeuta".
// Sin nombre de país usa un texto genérico corto. El editor y el admin conservan la etiqueta larga de arriba.
export function labelRateAudienceFor(code: string, countryName: string | null): string {
  if (code !== "own_country") return labelRateAudience(code);
  const name = countryName?.trim();
  return name ? `Residentes en ${name}` : "Residentes en el país";
}
export const labelLanguage =(code: string): string => LANGUAGES[code] ?? code;

export const SEARCH_GROUP_TITLES: Record<number, string> = {
  1: "En tu zona",
  2: "Atienden a distancia en tu país",
  3: "Atienden a distancia desde otros países",
};

// "En tu zona" only makes sense when the person chose a region or a city; with just a country (or nothing) the first group is
// simply "Resultados". / "En tu zona" solo tiene sentido si la persona eligió una región o una ciudad; con solo un país (o nada) el primer grupo es "Resultados".
export const terapeutasCount = (count: number): string => (count === 1 ? "1 terapeuta" : `${count} terapeutas`);

// A group heading with its own count: "En tu zona · 1 terapeuta". / Título de grupo con su propia cantidad.
export const groupHeading = (title: string, count: number): string => (title === "" ? terapeutasCount(count) : `${title} · ${terapeutasCount(count)}`);

export function searchGroupTitle(group: number, zoneChosen: boolean): string {
  if (group === 1 && !zoneChosen) return "Resultados";
  return SEARCH_GROUP_TITLES[group] ?? "";
}

// Joins labels with " y ": only the first keeps its capital letter ("Presencial y a distancia").
// Une etiquetas con " y ": solo la primera conserva la mayúscula ("Presencial y a distancia").
export function joinWithY(labels: readonly string[]): string {
  return labels.map((label, index) => (index === 0 ? label : label.charAt(0).toLowerCase() + label.slice(1))).join(" y ");
}
