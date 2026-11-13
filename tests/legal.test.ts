import { describe, expect, it } from "vitest";
import { LEGAL_DOCUMENTS, findLegalDocument } from "@/lib/legal";
import { CONTROLLER_ADDRESS, parseContactEmail } from "@/lib/legal/facts";
import { LEGAL_DOCUMENT_CODES } from "@/lib/legal/types";
import { LEGAL_REVIEW_PENDING, LEGAL_VERSIONS } from "@/lib/legal/versions";

describe("legal documents", () => {
  it("has one document per database code, with unique slugs", () => {
    expect(LEGAL_DOCUMENTS.map((d) => d.code).sort()).toEqual([...LEGAL_DOCUMENT_CODES].sort());
    expect(new Set(LEGAL_DOCUMENTS.map((d) => d.slug)).size).toBe(LEGAL_DOCUMENTS.length);
  });

  it("versions match the database regex", () => {
    for (const code of LEGAL_DOCUMENT_CODES) expect(LEGAL_VERSIONS[code]).toMatch(/^[A-Za-z0-9._-]{1,40}$/);
  });

  it("sections have unique ids and no empty blocks", () => {
    for (const doc of LEGAL_DOCUMENTS) {
      const ids = doc.sections.map((s) => s.id);
      expect(new Set(ids).size).toBe(ids.length);
      for (const s of doc.sections) {
        expect(s.blocks.length).toBeGreaterThan(0);
        for (const b of s.blocks) {
          if (b.type === "p") expect(b.text.trim()).not.toBe("");
          else expect(b.items.length).toBeGreaterThan(0);
        }
      }
    }
  });

  it("finds documents by slug", () => {
    expect(findLegalDocument("privacidad")?.code).toBe("privacy");
    expect(findLegalDocument("nada")).toBeUndefined();
  });

  it("does not claim health services or cures", () => {
    const terms = JSON.stringify(findLegalDocument("terminos"));
    expect(terms).toContain("No presta servicios de salud");
  });

  it("cannot go live without the controller address", () => {
    if (!LEGAL_REVIEW_PENDING) expect(CONTROLLER_ADDRESS).not.toBeNull();
  });

  it("parses the contact email", () => {
    expect(parseContactEmail("hola@example.com")).toBe("hola@example.com");
    expect(parseContactEmail("no-es-mail")).toBeNull();
    expect(parseContactEmail(undefined)).toBeNull();
  });
});
