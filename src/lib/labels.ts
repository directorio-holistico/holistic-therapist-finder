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
export const labelLanguage = (code: string): string => LANGUAGES[code] ?? code;

export const SEARCH_GROUP_TITLES: Record<number, string> = {
  1: "En tu zona",
  2: "Atienden a distancia en tu país",
  3: "Atienden a distancia desde otros países",
};
