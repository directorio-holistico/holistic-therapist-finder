// Re-acceptance of the legal documents: pure helpers shared by the banner, the server actions and the tests.
// The database decides WHAT is pending (my_pending_documents) and whether an acceptance is valid (accept_current_documents);
// this file only reads that answer, builds the payload from the versions of THIS deploy and recognises the gate's error.
// Re-aceptación de los documentos legales: funciones puras compartidas por el aviso, las acciones del servidor y las pruebas.
// La base decide QUÉ está pendiente (my_pending_documents) y si una aceptación es válida (accept_current_documents); este
// archivo solo lee esa respuesta, arma el envío con las versiones de ESTE despliegue y reconoce el error de la puerta.

import { LEGAL_DOCUMENTS } from "./index";
import { LEGAL_DOCUMENT_CODES, type LegalDocumentCode } from "./types";
import { LEGAL_VERSIONS } from "./versions";

// SQLSTATE raised by the database gate (assert_current_acceptances and the gate triggers). / SQLSTATE que levanta la puerta de la base.
export const ACCEPTANCE_REQUIRED_CODE = "AC001";

export const ACCEPTANCE_REQUIRED_MESSAGE =
  "Para cambiar tu perfil primero tenés que aceptar las versiones nuevas de los documentos legales. Lo hacés desde Mi perfil.";

export function isAcceptanceRequired(error: { code?: string | null } | null | undefined): boolean {
  return error?.code === ACCEPTANCE_REQUIRED_CODE;
}

// The database answers with a list of document codes. Anything unexpected returns null (fail closed: the caller shows an error
// instead of pretending nothing is pending).
// La base responde con una lista de códigos de documento. Cualquier cosa inesperada devuelve null (falla cerrado: quien llama
// muestra un error en vez de fingir que no hay nada pendiente).
export function parsePendingDocuments(value: unknown): LegalDocumentCode[] | null {
  if (!Array.isArray(value)) return null;
  const known = new Set<string>(LEGAL_DOCUMENT_CODES);
  const codes: LegalDocumentCode[] = [];
  for (const item of value) {
    if (typeof item !== "string" || !known.has(item)) return null;
    codes.push(item as LegalDocumentCode);
  }
  return codes;
}

// The acceptance sent to accept_current_documents: exactly the pending documents, each with the version published by this deploy.
// La aceptación que se manda a accept_current_documents: exactamente los documentos pendientes, cada uno con la versión publicada.
export function buildAcceptancePayload(pending: readonly LegalDocumentCode[]): Record<string, string> {
  return Object.fromEntries(pending.map((code) => [code, LEGAL_VERSIONS[code]]));
}

export type PendingDocumentLink = { code: LegalDocumentCode; title: string; href: string };

export function pendingDocumentLinks(pending: readonly LegalDocumentCode[]): PendingDocumentLink[] {
  const links: PendingDocumentLink[] = [];
  for (const code of pending) {
    const document = LEGAL_DOCUMENTS.find((candidate) => candidate.code === code);
    if (document) links.push({ code, title: document.title, href: `/legal/${document.slug}` });
  }
  return links;
}
