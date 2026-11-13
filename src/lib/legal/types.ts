// Shape of a legal document. The text lives as data (not as markup) so that the pages, the registration form and the tests
// all read the same source. / Forma de un documento legal. El texto vive como datos (no como marcado) para que las páginas,
// el formulario de alta y las pruebas lean la misma fuente.

export type LegalBlock = { type: "p"; text: string } | { type: "ul"; items: string[] };
export type LegalSection = { id: string; title: string; blocks: LegalBlock[] };

// Codes are the ones of the database table legal_document_types. / Los códigos son los de la tabla legal_document_types.
export const LEGAL_DOCUMENT_CODES = ["terms", "privacy", "legal_declaration", "offers_consent"] as const;
export type LegalDocumentCode = (typeof LEGAL_DOCUMENT_CODES)[number];

export type LegalDocument = {
  code: LegalDocumentCode;
  slug: string;
  title: string;
  summary: string;
  sections: LegalSection[];
};
