import { describe, expect, it } from "vitest";
import { INFO_DOCUMENTS, PUBLIC_PAGES, findPublicDocument } from "@/lib/legal";
import { INFO_VERSIONS } from "@/lib/legal/versions";

describe("informational legal pages (páginas legales informativas)", () => {
  it("every public page has a unique slug and can be found", () => {
    expect(new Set(PUBLIC_PAGES.map((d) => d.slug)).size).toBe(PUBLIC_PAGES.length);
    for (const doc of PUBLIC_PAGES) expect(findPublicDocument(doc.slug)).toBe(doc);
    expect(findPublicDocument("no-existe")).toBeUndefined();
  });

  it("informational pages are shown under /legal but have their own versions", () => {
    for (const doc of INFO_DOCUMENTS) {
      expect(PUBLIC_PAGES).toContain(doc);
      expect(INFO_VERSIONS[doc.code]).toMatch(/^[A-Za-z0-9._-]{1,40}$/);
    }
  });

  it("sections have unique ids and no empty text", () => {
    for (const doc of INFO_DOCUMENTS) {
      const ids = doc.sections.map((s) => s.id);
      expect(new Set(ids).size).toBe(ids.length);
      for (const section of doc.sections) {
        expect(section.blocks.length).toBeGreaterThan(0);
        for (const block of section.blocks) {
          if (block.type === "p") expect(block.text.trim().length).toBeGreaterThan(0);
          else for (const item of block.items) expect(item.trim().length).toBeGreaterThan(0);
        }
      }
    }
  });

  it("the cookies page names the session cookie and says there is no tracking", () => {
    const text = JSON.stringify(findPublicDocument("cookies"));
    expect(text).toContain("auth-token");
    expect(text).toContain("No usamos cookies de publicidad");
  });
});
