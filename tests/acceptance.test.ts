// Re-acceptance helpers: gate error recognition, safe reading of the database answer, payload and links.
// Ayudantes de re-aceptación: reconocer el error de la puerta, leer con seguridad la respuesta de la base, envío y enlaces.

import { describe, expect, it } from "vitest";
import {
  ACCEPTANCE_REQUIRED_CODE, buildAcceptancePayload, isAcceptanceRequired, parsePendingDocuments, pendingDocumentLinks,
} from "../src/lib/legal/acceptance";
import { LEGAL_DOCUMENT_CODES } from "../src/lib/legal/types";
import { LEGAL_VERSIONS } from "../src/lib/legal/versions";

describe("isAcceptanceRequired", () => {
  it("recognises only the gate's error code / reconoce solo el código de la puerta", () => {
    expect(ACCEPTANCE_REQUIRED_CODE).toBe("AC001");
    expect(isAcceptanceRequired({ code: "AC001" })).toBe(true);
    expect(isAcceptanceRequired({ code: "42501" })).toBe(false);
    expect(isAcceptanceRequired({ code: null })).toBe(false);
    expect(isAcceptanceRequired({})).toBe(false);
    expect(isAcceptanceRequired(null)).toBe(false);
    expect(isAcceptanceRequired(undefined)).toBe(false);
  });
});

describe("parsePendingDocuments", () => {
  it("accepts a list of known codes, also an empty one / acepta una lista de códigos conocidos, también vacía", () => {
    expect(parsePendingDocuments([])).toEqual([]);
    expect(parsePendingDocuments(["terms", "privacy"])).toEqual(["terms", "privacy"]);
  });
  it("fails closed on anything unexpected / falla cerrado ante cualquier cosa inesperada", () => {
    expect(parsePendingDocuments(null)).toBeNull();
    expect(parsePendingDocuments("terms")).toBeNull();
    expect(parsePendingDocuments({ 0: "terms" })).toBeNull();
    expect(parsePendingDocuments(["terms", "unknown_doc"])).toBeNull();
    expect(parsePendingDocuments(["terms", 3])).toBeNull();
  });
});

describe("buildAcceptancePayload", () => {
  it("has exactly the pending documents with the versions of this deploy / tiene justo los pendientes con las versiones de este despliegue", () => {
    expect(buildAcceptancePayload(["terms", "legal_declaration"])).toEqual({
      terms: LEGAL_VERSIONS.terms,
      legal_declaration: LEGAL_VERSIONS.legal_declaration,
    });
    expect(buildAcceptancePayload([])).toEqual({});
  });
  it("every version matches the format the database accepts / toda versión cumple el formato que acepta la base", () => {
    for (const code of LEGAL_DOCUMENT_CODES) expect(LEGAL_VERSIONS[code]).toMatch(/^[A-Za-z0-9._-]{1,40}$/);
  });
});

describe("pendingDocumentLinks", () => {
  it("links every document code to its legal page / enlaza cada código con su página legal", () => {
    const links = pendingDocumentLinks(LEGAL_DOCUMENT_CODES);
    expect(links.map((link) => link.code)).toEqual([...LEGAL_DOCUMENT_CODES]);
    for (const link of links) {
      expect(link.href).toMatch(/^\/legal\/[a-z0-9-]+$/);
      expect(link.title.length).toBeGreaterThan(0);
    }
  });
});
