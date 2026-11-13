// Facts the legal texts quote. They mirror the DEFAULTS of the database settings (app_settings) and the product rules; if a
// setting changes in the database, change it here too and raise the version of the affected document.
// Hechos que citan los textos legales. Reflejan los VALORES POR DEFECTO de los ajustes de la base (app_settings) y las reglas
// del producto; si un ajuste cambia en la base, cambiarlo acá también y subir la versión del documento afectado.

import { z } from "zod";

export const CONTROLLER_NAME = "Eduardo Ariel Vega";
// Legal address of the controller (null = still to complete; the pages say so).
// Domicilio legal del responsable (null = por completar; las páginas lo dicen).
export const CONTROLLER_ADDRESS: string | null = "Cinco Saltos, Río Negro, Argentina";

export const RETENTION = {
  unmetSearchesMonths: 12,
  contactRevealsMonths: 12,
  closedReportsMonths: 12,
  erasureFingerprintMonths: 12,
  auditLogMonths: 24,
  rateLimitDays: 2,
} as const;

export const REVIEW_BUSINESS_DAYS = { firstSubmission: 7, change: 3, priority: 1 } as const;
export const RATES_VALIDITY_MONTHS = 6;
export const MAX_THERAPIES_PER_PROFILE = 4;

// Contact email of the controller, read from the environment (never written in the repository). null if missing or invalid.
// Mail de contacto del responsable, leído del entorno (nunca escrito en el repositorio). null si falta o no es válido.
export function parseContactEmail(value: string | undefined): string | null {
  const parsed = z.email().safeParse((value ?? "").trim());
  return parsed.success ? parsed.data : null;
}

export function getContactEmail(): string | null {
  return parseContactEmail(process.env.CONTROLLER_CONTACT_EMAIL);
}
