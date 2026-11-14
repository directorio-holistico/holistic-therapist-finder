// What the administrator's report screens need to read and show: ids, filters, pages and Spanish labels. Pure functions, so every
// edge case is tested without a database. Nothing here decides who may do what: that is the database (is_admin() in each function).
// Lo que las pantallas de denuncias del administrador necesitan para leer y mostrar: ids, filtros, páginas y etiquetas en español.
// Funciones puras, así cada borde se prueba sin base. Nada de esto decide quién puede qué: eso lo decide la base (is_admin()).

import { REPORT_REASONS } from "@/lib/report-reasons";

export const REPORTS_PAGE_SIZE = 20;
const MAX_PAGE = 10000;

export type ReportFilter = "abiertas" | "cerradas";

// The id of a report is a whole number from the URL: digits only, no leading zero, small enough to be exact.
// El id de una denuncia es un número entero de la URL: solo dígitos, sin cero a la izquierda, lo bastante chico para ser exacto.
export function parseReportId(raw: string): number | null {
  if (!/^[1-9][0-9]{0,14}$/.test(raw)) return null;
  const value = Number(raw);
  return Number.isSafeInteger(value) ? value : null;
}

const first = (value: string | string[] | undefined): string | undefined => (Array.isArray(value) ? value[0] : value);

export function parseFilter(raw: string | string[] | undefined): ReportFilter {
  return first(raw) === "cerradas" ? "cerradas" : "abiertas";
}

export function parsePage(raw: string | string[] | undefined): number {
  const text = first(raw);
  if (text === undefined || !/^[1-9][0-9]{0,4}$/.test(text)) return 1;
  return Math.min(Number(text), MAX_PAGE);
}

// The row range of a page (both ends included, as .range() wants them). / El rango de filas de una página (ambos extremos incluidos).
export function pageRange(page: number): { from: number; to: number } {
  const from = (page - 1) * REPORTS_PAGE_SIZE;
  return { from, to: from + REPORTS_PAGE_SIZE - 1 };
}

export function hasNextPage(page: number, total: number): boolean {
  return page * REPORTS_PAGE_SIZE < total;
}

// An unknown code is shown as it is, so a new catalog row never breaks the screen. / Un código desconocido se muestra tal cual.
export function reasonLabel(code: string): string {
  return REPORT_REASONS.find((reason) => reason.code === code)?.label ?? code;
}

const REPORT_STATUS_LABELS: Record<string, string> = { open: "Abierta", dismissed: "Descartada", resolved: "Resuelta" };
export const reportStatusLabel = (code: string): string => REPORT_STATUS_LABELS[code] ?? code;

const PROFILE_STATUS_LABELS: Record<string, string> = {
  unpublished: "No publicado", published: "Publicado", paused: "Pausado", suspended: "Suspendido", erased: "Eliminado",
};
export const profileStatusLabel = (code: string): string => PROFILE_STATUS_LABELS[code] ?? code;

// Which profile actions make sense for a status. The database re-checks both (55000 when the state does not allow it).
// Qué acciones sobre el perfil tienen sentido para un estado. La base vuelve a revisar ambas (55000 si el estado no lo permite).
export const canSuspend = (code: string): boolean => code !== "suspended" && code !== "erased";
export const canReinstate = (code: string): boolean => code === "suspended";

export const RESULT_NOTICES: Record<string, string> = {
  cerrada: "La denuncia quedó cerrada.",
  suspendido: "El perfil quedó suspendido y ya no es público. La denuncia sigue abierta: cerrala cuando termines.",
  repuesto: "El perfil volvió a estar disponible. La denuncia sigue como estaba.",
};
