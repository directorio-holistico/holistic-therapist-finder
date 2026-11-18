// Version of each legal document. The registration stores THIS string next to the acceptance (register_therapist), so any
// change of wording must change the version here, and a substantial change asks the therapists to accept again.
// The database accepts versions of 1 to 40 characters: letters, digits, dot, underscore and hyphen.
// Versión de cada documento legal. El alta guarda ESTA cadena junto a la aceptación (register_therapist); todo cambio de texto
// debe cambiar la versión acá, y un cambio sustancial pide a los terapeutas aceptar de nuevo.

import type { InfoDocumentCode, LegalDocumentCode } from "./types";

export const LEGAL_VERSIONS: Record<LegalDocumentCode, string> = {
  terms: "2026-11-e",
  privacy: "2026-11-e",
  legal_declaration: "2026-11-a",
  offers_consent: "2026-11-a",
};

// Version of each informational page (no acceptance is stored for them). Change it when the wording changes.
// Versión de cada página informativa (no se guarda aceptación). Cambiarla cuando cambie el texto.
export const INFO_VERSIONS: Record<InfoDocumentCode, string> = {
  legal_notice: "2026-11-b",
  cookies: "2026-11-a",
};

export const LEGAL_UPDATED_LABEL = "18 de noviembre de 2026";

// TRUE while no lawyer has reviewed the texts: every page shows a visible notice. Set it to false ONLY after the review
// (the tests then require the controller's address, so nobody launches with a placeholder).
// TRUE mientras ningún abogado revisó los textos: todas las páginas muestran un aviso visible. Pasarlo a false SOLO tras la
// revisión (las pruebas exigen entonces el domicilio del responsable, para no salir con un dato a completar).
// 2026-11-18: the controller set it to false on his own decision, before any lawyer review. A professional review is still pending.
// 2026-11-18: el responsable lo pasó a false por decisión propia, antes de una revisión de abogado. La revisión profesional sigue pendiente.
export const LEGAL_REVIEW_PENDING = false;
