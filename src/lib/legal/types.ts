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

// Informational pages: they have no acceptance and no row in legal_document_types, so they are NOT in LEGAL_DOCUMENT_CODES.
// Páginas informativas: no se aceptan y no tienen fila en legal_document_types, por eso NO están en LEGAL_DOCUMENT_CODES.
export type InfoDocumentCode = "legal_notice" | "cookies";
export type InfoDocument = Omit<LegalDocument, "code"> & { code: InfoDocumentCode };
