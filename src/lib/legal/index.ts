import { DECLARATION } from "./declaration";
import { OFFERS } from "./offers";
import { PRIVACY } from "./privacy";
import { TERMS } from "./terms";
import type { LegalDocument } from "./types";

// Order = order shown in the index page and in the footer. / Orden = el de la página índice y el pie.
export const LEGAL_DOCUMENTS: readonly LegalDocument[] = [TERMS, PRIVACY, DECLARATION, OFFERS];

export function findLegalDocument(slug: string): LegalDocument | undefined {
  return LEGAL_DOCUMENTS.find((doc) => doc.slug === slug);
}
