// Problems found in a revision before approving, and the rejection reason built from them (pure code, no database).
// Problemas de una revisión antes de aprobar, y el motivo de rechazo armado con ellos (código puro, sin base).

import { describe, expect, it } from "vitest";
import type { ViewLookups } from "@/lib/admin/revision-view";
import { revisionProblems, suggestedReason } from "@/lib/admin/revision-problems";

const LOOKUPS: ViewLookups = {
  therapies: new Map([[10, "Reiki"], [29, "Psicoanálisis"]]),
  inactiveTherapies: new Set([29]),
  currencies: new Map([[1, "EUR"]]),
  audiences: new Map([[1, "Residentes"]]),
  languages: new Map([[1, "Español"]]),
  serviceModes: new Map([[1, "Presencial"]]),
  sessionFormats: new Map([[1, "Individual"]]),
  contactTypes: new Map([[1, "phone"], [2, "email"], [3, "website"], [4, "instagram"], [5, "facebook"]]),
};
const OK = { locationActive: true };

const therapy = () => ({ therapy_id: 10, description: "Sesiones tranquilas", service_modes: [1], session_formats: [1], rates: [{ rate_audience_id: 1, amount: 20, currency_id: 1 }] });
const clean = () => ({
  display_name: "Ana",
  headline: "Facilitadora de Reiki",
  about: "Trabajo desde hace años con personas de mi barrio.",
  location_id: 5,
  languages: [1],
  therapies: [therapy()],
  contacts: [
    { contact_type_id: 1, value: "+34627973392", accepts_whatsapp: true },
    { contact_type_id: 2, value: "ana@example.com" },
    { contact_type_id: 4, value: "ana.terapias" },
  ],
});

describe("revisionProblems", () => {
  it("finds nothing in a correct revision", () => {
    expect(revisionProblems(clean(), LOOKUPS, OK)).toEqual([]);
  });

  it("names a hidden therapy (the case that blocked an approval)", () => {
    const payload = { ...clean(), therapies: [...clean().therapies, { therapy_id: 29, service_modes: [1], session_formats: [1] }] };
    const problems = revisionProblems(payload, LOOKUPS, OK);
    expect(problems).toHaveLength(1);
    expect(problems[0]).toContain("Psicoanálisis");
  });

  it("flags a therapy that does not exist and a city that is not active", () => {
    const payload = { ...clean(), therapies: [{ therapy_id: 999, service_modes: [1], session_formats: [1] }] };
    expect(revisionProblems(payload, LOOKUPS, { locationActive: false })).toHaveLength(2);
  });

  it("does not flag the city when it is unknown (not read)", () => {
    expect(revisionProblems(clean(), LOOKUPS, { locationActive: null })).toEqual([]);
  });

  it("flags contact data inside the free texts", () => {
    const payload = { ...clean(), about: "Escribime a ana@example.com o al 11 5555 4444", therapies: [{ ...therapy(), description: "Seguime en @ana.terapias" }] };
    const problems = revisionProblems(payload, LOOKUPS, OK);
    expect(problems).toHaveLength(2);
    expect(problems.join(" ")).toContain("Sobre mí");
    expect(problems.join(" ")).toContain("Reiki");
  });

  it("flags texts that are too long", () => {
    const payload = { ...clean(), headline: "x".repeat(281), about: "y".repeat(1501) };
    expect(revisionProblems(payload, LOOKUPS, OK)).toHaveLength(2);
  });

  it("flags contacts with the wrong format (phone, e-mail with capitals, Instagram as a link)", () => {
    const payload = {
      ...clean(),
      contacts: [
        { contact_type_id: 1, value: "12ab" },
        { contact_type_id: 2, value: "Ana@Example.com" },
        { contact_type_id: 4, value: "https://www.instagram.com/ana" },
      ],
    };
    expect(revisionProblems(payload, LOOKUPS, OK)).toHaveLength(3);
  });

  it("flags options that are no longer available", () => {
    const payload = {
      ...clean(),
      languages: [7],
      therapies: [{ therapy_id: 10, service_modes: [9], session_formats: [9], rates: [{ rate_audience_id: 9, amount: 1, currency_id: 1 }] }],
      contacts: [{ contact_type_id: 99, value: "x" }],
    };
    expect(revisionProblems(payload, LOOKUPS, OK)).toHaveLength(5);
  });

  it("tells the same problem once", () => {
    const hidden = { therapy_id: 29, service_modes: [1], session_formats: [1] };
    expect(revisionProblems({ ...clean(), therapies: [hidden, hidden] }, LOOKUPS, OK)).toHaveLength(1);
  });

  it("returns nothing for a payload that is not an object", () => {
    expect(revisionProblems("nope", LOOKUPS, OK)).toEqual([]);
    expect(revisionProblems(null, LOOKUPS, OK)).toEqual([]);
  });
});

describe("suggestedReason", () => {
  it("is empty when there are no problems", () => {
    expect(suggestedReason([])).toBe("");
  });

  it("lists the problems for the therapist and says how to continue", () => {
    const text = suggestedReason(["Primero.", "Segundo."]);
    expect(text).toContain("- Primero.");
    expect(text).toContain("- Segundo.");
    expect(text).toContain("volvé a enviarlo");
  });

  it("never passes the 1000 characters the rejection reason accepts", () => {
    const many = Array.from({ length: 40 }, (_, index) => `Problema número ${index} con un texto bastante largo para llenar el espacio disponible.`);
    expect(suggestedReason(many).length).toBeLessThanOrEqual(1000);
  });
});

describe("revision with no therapies", () => {
  it("is stopped, and says which therapy was asked for", () => {
    const payload = { ...clean(), therapies: [] };
    expect(revisionProblems(payload, LOOKUPS, { ...OK, suggestedTherapy: "Hipnoterapia ericksoniana" })).toEqual([
      "Pediste agregar «Hipnoterapia ericksoniana». La estamos evaluando; si la agregamos, te avisamos para que la elijas en tu perfil.",
    ]);
  });
  it("asks to choose one when nothing was asked for", () => {
    expect(revisionProblems({ ...clean(), therapies: [] }, LOOKUPS, OK)).toEqual(["No elegiste ninguna terapia. Elegí al menos una."]);
    expect(revisionProblems({ ...clean(), therapies: [] }, LOOKUPS, { ...OK, suggestedTherapy: "   " })).toEqual(["No elegiste ninguna terapia. Elegí al menos una."]);
  });
  it("does not complain when the payload does not touch the therapies", () => {
    const withoutTherapies: Record<string, unknown> = { ...clean() };
    delete withoutTherapies["therapies"];
    expect(revisionProblems(withoutTherapies, LOOKUPS, OK)).toEqual([]);
  });
});
