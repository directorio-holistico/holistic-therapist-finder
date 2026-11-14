import { describe, expect, it } from "vitest";
import { decisionFacts, describeRevision, safeHref, type ViewLookups } from "@/lib/admin/revision-view";

const LOOKUPS: ViewLookups = {
  therapies: new Map([[10, "Reiki"]]),
  currencies: new Map([[1, "ARS"]]),
  audiences: new Map([[1, "Residentes"], [2, "Exterior"]]),
  languages: new Map([[1, "Español"]]),
  serviceModes: new Map([[1, "Presencial"]]),
  sessionFormats: new Map([[1, "Individual"]]),
  contactTypes: new Map([[1, "phone"], [2, "email"], [3, "website"], [4, "instagram"], [5, "facebook"], [6, "tiktok"], [7, "youtube"]]),
};

describe("safeHref (a link opens only if it has the strict format)", () => {
  it("accepts the expected shapes", () => {
    expect(safeHref("website", "https://ana.example/terapias")).toBe("https://ana.example/terapias");
    expect(safeHref("instagram", "ana.terapias")).toBe("https://www.instagram.com/ana.terapias");
    expect(safeHref("facebook", "https://www.facebook.com/anaterapias")).toBe("https://www.facebook.com/anaterapias");
    expect(safeHref("tiktok", "https://www.tiktok.com/@ana.terapias")).toBe("https://www.tiktok.com/@ana.terapias");
    expect(safeHref("youtube", "https://www.youtube.com/@anaterapias")).toBe("https://www.youtube.com/@anaterapias");
  });

  it("never opens scripts, other schemes, look-alike hosts or text with spaces", () => {
    for (const bad of ["javascript:alert(1)", "data:text/html,<b>x</b>", "ftp://x.test/a", "//evil.test", "https://a.test/a b", "ana"]) {
      expect(safeHref("website", bad), bad).toBeNull();
    }
    for (const bad of ["@ana", "https://instagram.com/ana", "ana terapias", "A"]) expect(safeHref("instagram", bad), bad).toBeNull();
    expect(safeHref("facebook", "https://facebook.com.evil.test/x")).toBeNull();
    expect(safeHref("facebook", "javascript:alert(1)")).toBeNull();
    expect(safeHref("tiktok", "https://vm.tiktok.com/abc")).toBeNull();
    expect(safeHref("youtube", "https://youtu.be/abc")).toBeNull();
  });
});

describe("describeRevision", () => {
  const payload = {
    display_name: "<img src=x onerror=alert(1)>Ana",
    headline: "Hola",
    location_id: 79,
    languages: [1],
    therapies: [
      { therapy_id: 10, session_minutes: 60, service_modes: [1], session_formats: [1], rates: [{ rate_audience_id: 1, amount: 15000, currency_id: 1 }] },
      { therapy_id: 99 },
    ],
    contacts: [
      { contact_type_id: 1, value: "+54 299 555 0101", accepts_whatsapp: true },
      { contact_type_id: 2, value: "ana@example.com" },
      { contact_type_id: 3, value: "javascript:alert(1)" },
      { contact_type_id: 4, value: "ana.terapias" },
    ],
  };

  it("resolves names, keeps text as text and marks bad links without a href", () => {
    const view = describeRevision(payload, LOOKUPS);
    expect(view).not.toBeNull();
    if (!view) return;
    expect(view.displayName).toBe("<img src=x onerror=alert(1)>Ana"); // plain text: React escapes it on screen
    expect(view.therapies[0]).toEqual({
      name: "Reiki", minutes: 60, serviceModes: ["Presencial"], sessionFormats: ["Individual"],
      rates: [{ audience: "Residentes", amount: 15000, currency: "ARS" }],
    });
    // a therapy without lists (an old payload) shows empty lists, never invented ones / sin listas (payload viejo): listas vacías
    expect(view.therapies[1]).toMatchObject({ name: "#99", serviceModes: [], sessionFormats: [] });
    expect(view.links).toEqual([
      { kind: "website", value: "javascript:alert(1)", href: null },
      { kind: "instagram", value: "ana.terapias", href: "https://www.instagram.com/ana.terapias" },
    ]);
  });

  it("never exposes the phone or the e-mail values", () => {
    const view = describeRevision(payload, LOOKUPS);
    expect(view?.hasPhone).toBe(true);
    expect(view?.phoneWhatsapp).toBe(true);
    expect(view?.hasEmail).toBe(true);
    expect(JSON.stringify(view)).not.toContain("555 0101");
    expect(JSON.stringify(view)).not.toContain("ana@example.com");
  });

  it("returns null for anything that is not the expected shape", () => {
    for (const bad of [null, "texto", 5, [], { languages: "no" }, { contacts: [{ value: 3 }] }]) expect(describeRevision(bad, LOOKUPS), JSON.stringify(bad)).toBeNull();
  });
});

describe("decisionFacts", () => {
  it("tells whether there is a city and how many public links must be checked", () => {
    const types = LOOKUPS.contactTypes;
    expect(decisionFacts({ location_id: 5, contacts: [{ contact_type_id: 1, value: "1" }, { contact_type_id: 3, value: "x" }, { contact_type_id: 7, value: "y" }] }, types))
      .toEqual({ hasCity: true, linksToCheck: 2 });
    expect(decisionFacts({ location_id: null }, types)).toEqual({ hasCity: false, linksToCheck: 0 });
    expect(decisionFacts("basura", types)).toBeNull();
  });
});
