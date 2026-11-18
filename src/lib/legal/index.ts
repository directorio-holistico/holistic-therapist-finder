import { COOKIES } from "./cookies";
import { DECLARATION } from "./declaration";
import { NOTICE } from "./notice";
import { OFFERS } from "./offers";
import { PRIVACY } from "./privacy";
import { TERMS } from "./terms";
import type { InfoDocument, LegalDocument } from "./types";

// Order = order shown in the index page and in the footer. / Orden = el de la página índice y el pie.
export const LEGAL_DOCUMENTS: readonly LegalDocument[] = [TERMS, PRIVACY, DECLARATION, OFFERS];

export function findLegalDocument(slug: string): LegalDocument | undefined {
  return LEGAL_DOCUMENTS.find((doc) => doc.slug === slug);
}

// Informational pages (no acceptance). / Páginas informativas (sin aceptación).
export const INFO_DOCUMENTS: readonly InfoDocument[] = [NOTICE, COOKIES];

// Everything shown under /legal, in this order. / Todo lo que se muestra en /legal, en este orden.
export const PUBLIC_PAGES: readonly (LegalDocument | InfoDocument)[] = [NOTICE, TERMS, PRIVACY, COOKIES, DECLARATION, OFFERS];

export function findPublicDocument(slug: string): LegalDocument | InfoDocument | undefined {
  return PUBLIC_PAGES.find((doc) => doc.slug === slug);
}
