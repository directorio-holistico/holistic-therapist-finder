import { describe, expect, it } from "vitest";
import { buildAcceptances, readRegistrationForm, registrationErrorMessage } from "@/lib/registration";
import { LEGAL_VERSIONS } from "@/lib/legal/versions";

function form(fields: Record<string, string>): FormData {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}
const REQUIRED = { terms: "on", privacy: "on", legalDeclaration: "on" };

describe("registration form", () => {
  it("accepts a valid form and cleans the name", () => {
    const parsed = readRegistrationForm(form({ fullName: "  Lucía   Ferrante ", ...REQUIRED }));
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.fullName).toBe("Lucía Ferrante");
      expect(parsed.data.offers).toBe(false);
    }
  });

  it("rejects an empty or too long name", () => {
    expect(readRegistrationForm(form({ fullName: "   ", ...REQUIRED })).success).toBe(false);
    expect(readRegistrationForm(form({ fullName: "a".repeat(121), ...REQUIRED })).success).toBe(false);
    expect(readRegistrationForm(form({ fullName: "a".repeat(120), ...REQUIRED })).success).toBe(true);
  });

  it.each(["terms", "privacy", "legalDeclaration"])("requires %s", (missing) => {
    const fields: Record<string, string> = { fullName: "Ana", ...REQUIRED };
    delete fields[missing];
    expect(readRegistrationForm(form(fields)).success).toBe(false);
  });
});

describe("acceptances", () => {
  it("leaves the optional consent out unless it is checked", () => {
    expect(buildAcceptances({ offers: false })).toEqual({
      terms: LEGAL_VERSIONS.terms,
      privacy: LEGAL_VERSIONS.privacy,
      legal_declaration: LEGAL_VERSIONS.legal_declaration,
    });
    expect(buildAcceptances({ offers: true }).offers_consent).toBe(LEGAL_VERSIONS.offers_consent);
  });
});

describe("error messages", () => {
  it("maps known codes and hides the rest", () => {
    expect(registrationErrorMessage("42501")).toContain("ingresar");
    expect(registrationErrorMessage("22023")).toContain("Revisá");
    expect(registrationErrorMessage("XX000")).toContain("No pudimos");
    expect(registrationErrorMessage(undefined)).toContain("No pudimos");
  });
});
