// Preview of the therapist's own profile: saved values -> the same card and profile the public pages draw (pure; no network).
// Vista previa del propio perfil: valores guardados -> la misma tarjeta y perfil que dibujan las páginas públicas (pura; sin red).

import { describe, expect, it } from "vitest";
import type { FormCatalogs, LocationTree } from "../src/lib/catalogs";
import { EMPTY_DEFAULTS, padTherapies, type FormDefaults, type TherapyDefaults } from "../src/lib/profile-form";
import { buildPreview, type PreviewInput } from "../src/lib/profile-preview";

const PROFILE_ID = "20000000-0000-0000-0000-0000000029a1";

const catalogs: FormCatalogs = {
  languages: [{ id: 1, code: "es" }, { id: 2, code: "en" }],
  serviceModes: [{ id: 1, code: "in_person" }, { id: 2, code: "remote" }],
  sessionFormats: [{ id: 1, code: "individual" }, { id: 2, code: "group" }],
  contactTypes: [],
  therapies: [{ id: 10, name: "Reiki" }, { id: 24, name: "LNT® - La Nueva Terapia" }],
  currencies: [{ id: 1, code: "ARS", minorUnits: 2 }, { id: 2, code: "USD", minorUnits: 2 }],
  rateAudiences: [{ id: 1, code: "own_country" }, { id: 2, code: "other_countries" }],
};
const tree: LocationTree = {
  countries: [{ id: 1, name: "Argentina" }],
  regions: [{ id: 2, name: "Buenos Aires", parentId: 1 }],
  cities: [{ id: 3, name: "Olivos", parentId: 2 }],
};

const slot = (overrides: Partial<TherapyDefaults>): TherapyDefaults => ({
  therapyId: 10, description: "", minutes: "", rateOwn: "", rateOther: "", serviceModes: [1], sessionFormats: [1], ...overrides,
});
const defaultsWith = (overrides: Partial<FormDefaults>): FormDefaults => ({
  ...EMPTY_DEFAULTS,
  displayName: "Lucía Ferrante",
  cityId: 3,
  therapies: padTherapies([slot({})]),
  ...overrides,
});
const input = (defaults: FormDefaults, overrides: Partial<PreviewInput> = {}): PreviewInput => ({
  profileId: PROFILE_ID, defaults, catalogs, tree, countryIso: "AR", isPinned: false, shortNames: new Map(), livePhotoPath: null, ...overrides,
});

describe("buildPreview", () => {
  it("has nothing to draw without a public name", () => {
    expect(buildPreview(input(defaultsWith({ displayName: "   " })))).toBeNull();
  });

  it("draws the place and the flag like the public pages", () => {
    const preview = buildPreview(input(defaultsWith({ headline: "Sesiones de Reiki" })));
    expect(preview?.card.place).toBe("Olivos, Buenos Aires, Argentina");
    expect(preview?.card.countryIso).toBe("AR");
    expect(preview?.detail.place).toBe("Olivos, Buenos Aires, Argentina");
    expect(preview?.detail.headline).toBe("Sesiones de Reiki");
  });

  it("works with no city chosen yet (no place, no crash)", () => {
    const preview = buildPreview(input(defaultsWith({ cityId: null }), { countryIso: null }));
    expect(preview?.card.place).toBe("");
    expect(preview?.card.countryIso).toBeNull();
  });

  it("uses the short name on the card and the full name on the profile", () => {
    const defaults = defaultsWith({ therapies: padTherapies([slot({ therapyId: 24 }), slot({ therapyId: 10 })]) });
    const preview = buildPreview(input(defaults, { shortNames: new Map([[24, "LNT®"]]) }));
    expect(preview?.card.therapies).toEqual(["LNT® - La Nueva Terapia", "Reiki"]);
    expect(preview?.card.therapyShorts).toEqual(["LNT®", "Reiki"]);
    expect(preview?.detail.therapies.map((item) => item.name)).toEqual(["LNT® - La Nueva Terapia", "Reiki"]);
  });

  it("skips empty rows and therapies that are not in the active catalog", () => {
    const defaults = defaultsWith({ therapies: padTherapies([slot({ therapyId: 999 }), slot({ therapyId: 10 })]) });
    const preview = buildPreview(input(defaults));
    expect(preview?.detail.therapies.map((item) => item.therapyId)).toEqual([10]);
  });

  it("shows the modes of all therapies once, in the catalog order", () => {
    const defaults = defaultsWith({ therapies: padTherapies([slot({ therapyId: 10, serviceModes: [2] }), slot({ therapyId: 24, serviceModes: [1] })]) });
    expect(buildPreview(input(defaults))?.card.serviceModes).toEqual(["in_person", "remote"]);
  });

  it("reads Argentine-style prices and leaves out a price with no currency or a wrong amount", () => {
    const defaults = defaultsWith({
      therapies: padTherapies([slot({ rateOwn: "20.000", rateOther: "abc" })]),
      currencyOwn: 1,
      currencyOther: 2,
    });
    const rates = buildPreview(input(defaults))?.detail.therapies[0]?.rates;
    expect(rates).toEqual([{ audience: "own_country", amount: 20000, currency: "ARS" }]);
    const noCurrency = buildPreview(input(defaultsWith({ therapies: padTherapies([slot({ rateOwn: "20000" })]), currencyOwn: null })));
    expect(noCurrency?.detail.therapies[0]?.rates).toEqual([]);
  });

  it("does not claim the prices are confirmed (a draft has no confirmation date)", () => {
    const detail = buildPreview(input(defaultsWith({ therapies: padTherapies([slot({ rateOwn: "100" })]), currencyOwn: 1 })))?.detail;
    expect(detail?.ratesConfirmedAt).toBeNull();
    expect(detail?.ratesCurrent).toBe(false);
  });

  it("decides the photo: pending first, then the live one, and none when she asked to remove it", () => {
    const live = "20000000-0000-0000-0000-0000000029a1/live.jpg";
    const pending = "20000000-0000-0000-0000-0000000029a1/new.jpg";
    expect(buildPreview(input(defaultsWith({ photoNew: pending }), { livePhotoPath: live }))?.photo).toEqual({ kind: "pending", path: pending });
    expect(buildPreview(input(defaultsWith({}), { livePhotoPath: live }))?.photo).toEqual({ kind: "live", path: live });
    expect(buildPreview(input(defaultsWith({ photoRemove: true }), { livePhotoPath: live }))?.photo).toEqual({ kind: "none" });
    expect(buildPreview(input(defaultsWith({})))?.photo).toEqual({ kind: "none" });
    // a pending path is never put in the public-bucket path of the card / una ruta pendiente nunca va en la ruta del bucket público de la tarjeta
    expect(buildPreview(input(defaultsWith({ photoNew: pending }), { livePhotoPath: live }))?.card.photoPath).toBeNull();
    expect(buildPreview(input(defaultsWith({}), { livePhotoPath: live }))?.card.photoPath).toBe(live);
  });

  it("keeps only safe links", () => {
    const defaults = defaultsWith({ website: "javascript:alert(1)", instagram: "lucia.reiki", facebook: "https://evil.example/lucia" });
    const links = buildPreview(input(defaults))?.detail.links ?? [];
    expect(links.map((link) => link.kind)).toEqual(["instagram"]);
  });

  it("never carries the phone or the mail", () => {
    const defaults = defaultsWith({ phone: "+54 9 11 5555-1234", email: "lucia@example.com", phoneWhatsapp: true });
    const text = JSON.stringify(buildPreview(input(defaults)));
    expect(text).not.toContain("5555-1234");
    expect(text).not.toContain("lucia@example.com");
  });

  it("marks the pinned founder like the public pages do", () => {
    const preview = buildPreview(input(defaultsWith({}), { isPinned: true }));
    expect(preview?.card.isPinned).toBe(true);
    expect(preview?.detail.isPinned).toBe(true);
  });
});
