import { describe, expect, it } from "vitest";
import { buildChildOptions } from "@/lib/catalogs";
import { buildPayload, defaultsFromPayload, EMPTY_DEFAULTS, instagramIsValid, normalizeInstagram, phoneIsValid, readProfileForm } from "@/lib/profile-form";

const YEAR = 2026;
const TYPES = { phone: 1, email: 2, website: 3, instagram: 4 };

function form(fields: Record<string, string | string[]>): FormData {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) {
    if (Array.isArray(value)) value.forEach((item) => data.append(key, item));
    else data.set(key, value);
  }
  return data;
}
const VALID = {
  displayName: "  Lucía   Ferrante ",
  cityId: "7",
  languages: ["1"],
  serviceModes: ["1", "2"],
  sessionFormats: ["1"],
  phone: "+54 299 555 0101",
};

describe("profile form", () => {
  it("accepts a minimal valid form and cleans the text", () => {
    const parsed = readProfileForm(form(VALID), YEAR);
    expect(parsed.success).toBe(true);
    if (!parsed.success) return;
    expect(parsed.data.displayName).toBe("Lucía Ferrante");
    expect(parsed.data.headline).toBeNull();
    expect(parsed.data.email).toBeNull();
    expect(parsed.data.website).toBeNull();
    expect(parsed.data.cityId).toBe(7);
  });

  it("requires name, phone, a city and at least one language, mode and format", () => {
    for (const missing of ["displayName", "phone", "cityId", "languages", "serviceModes", "sessionFormats"]) {
      const fields: Record<string, string | string[]> = { ...VALID };
      delete fields[missing];
      expect(readProfileForm(form(fields), YEAR).success, missing).toBe(false);
    }
  });

  it("validates the phone like the database does", () => {
    expect(phoneIsValid("+54 (299) 555-0101")).toBe(true);
    expect(phoneIsValid("12345")).toBe(false);
    expect(phoneIsValid("1234567890123456")).toBe(false);
    expect(phoneIsValid("abc 123456")).toBe(false);
  });

  it("lower-cases the email, completes the website and rejects bad ones", () => {
    const ok = readProfileForm(form({ ...VALID, email: " Hola@Ejemplo.com ", website: "ejemplo.com/yo" }), YEAR);
    expect(ok.success && ok.data.email).toBe("hola@ejemplo.com");
    expect(ok.success && ok.data.website).toBe("https://ejemplo.com/yo");
    expect(readProfileForm(form({ ...VALID, email: "sin-arroba" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, website: "https://con espacio.com" }), YEAR).success).toBe(false);
  });

  it("limits the lengths and the start year", () => {
    expect(readProfileForm(form({ ...VALID, headline: "a".repeat(281) }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, headline: "a".repeat(280) }), YEAR).success).toBe(true);
    expect(readProfileForm(form({ ...VALID, practiceStartYear: "1899" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, practiceStartYear: "2027" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, practiceStartYear: "2015" }), YEAR).success).toBe(true);
  });

  it("a city that is not listed needs a region and a name, and no city id", () => {
    const { cityId: _omit, ...rest } = VALID;
    void _omit;
    expect(readProfileForm(form({ ...rest, cityMissing: "on" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...rest, cityMissing: "on", regionId: "3" }), YEAR).success).toBe(false);
    const ok = readProfileForm(form({ ...rest, cityMissing: "on", regionId: "3", cityName: " Villa  Regina " }), YEAR);
    expect(ok.success).toBe(true);
    if (ok.success) expect(buildPayload(ok.data, TYPES).location_id).toBeNull();
  });

  it("ignores unreadable numbers instead of trusting them", () => {
    const parsed = readProfileForm(form({ ...VALID, languages: ["1", "x", "-3", "1.5"] }), YEAR);
    expect(parsed.success && parsed.data.languages).toEqual([1]);
  });
});

describe("instagram", () => {
  it("keeps only the user name, in lower case", () => {
    for (const raw of ["@Ana.Terapias", "ana.terapias", " https://www.instagram.com/Ana.Terapias/?hl=es ", "instagram.com/ana.terapias#x"]) {
      expect(normalizeInstagram(raw), raw).toBe("ana.terapias");
    }
    expect(normalizeInstagram("   ")).toBe("");
  });

  it("validates the format the database enforces", () => {
    expect(instagramIsValid("ana_30.x")).toBe(true);
    expect(instagramIsValid("a".repeat(30))).toBe(true);
    expect(instagramIsValid("a".repeat(31))).toBe(false);
    expect(instagramIsValid("con espacio")).toBe(false);
    expect(instagramIsValid("ñandú")).toBe(false);
  });

  it("is optional, becomes a public contact and rejects garbage", () => {
    const none = readProfileForm(form(VALID), YEAR);
    expect(none.success && none.data.instagram).toBeNull();
    const ok = readProfileForm(form({ ...VALID, instagram: "@Ana.Terapias" }), YEAR);
    if (!ok.success) throw new Error("must parse");
    expect(buildPayload(ok.data, TYPES).contacts.at(-1)).toEqual({ contact_type_id: 4, value: "ana.terapias", accepts_whatsapp: false });
    expect(readProfileForm(form({ ...VALID, instagram: "no valido!" }), YEAR).success).toBe(false);
  });
});

describe("payload", () => {
  it("uses only the keys the database knows and puts the phone first", () => {
    const parsed = readProfileForm(form({ ...VALID, email: "a@b.co", phoneWhatsapp: "on", languages: ["2", "1", "2"] }), YEAR);
    if (!parsed.success) throw new Error("must parse");
    const payload = buildPayload(parsed.data, TYPES);
    expect(Object.keys(payload).sort()).toEqual([
      "contacts", "display_name", "headline", "languages", "location_id", "practice_start_year", "service_modes", "session_formats", "zone",
    ]);
    expect(payload.languages).toEqual([1, 2]);
    expect(payload.contacts).toEqual([
      { contact_type_id: 1, value: "+54 299 555 0101", accepts_whatsapp: true },
      { contact_type_id: 2, value: "a@b.co", accepts_whatsapp: false },
    ]);
  });

  it("round-trips through defaultsFromPayload and survives garbage", () => {
    const parsed = readProfileForm(form({ ...VALID, headline: "Hola", zone: "Centro", practiceStartYear: "2015" }), YEAR);
    if (!parsed.success) throw new Error("must parse");
    const back = defaultsFromPayload(buildPayload(parsed.data, TYPES), TYPES);
    expect(back).toMatchObject({ displayName: "Lucía Ferrante", headline: "Hola", zone: "Centro", practiceStartYear: "2015", cityId: 7, phone: "+54 299 555 0101" });
    expect(defaultsFromPayload("basura", TYPES)).toEqual(EMPTY_DEFAULTS);
    expect(defaultsFromPayload({ languages: "no" }, TYPES)).toEqual(EMPTY_DEFAULTS);
  });
});

describe("location tree helper", () => {
  it("groups children under their parent, sorted in Spanish, dropping orphans", () => {
    const options = buildChildOptions(
      [{ id: 1, parent_id: 10 }, { id: 2, parent_id: 10 }, { id: 3, parent_id: null }],
      [{ id: 1, name: "Zárate" }, { id: 2, name: "Ávila" }, { id: 3, name: "Sin padre" }],
    );
    expect(options).toEqual([{ id: 2, name: "Ávila", parentId: 10 }, { id: 1, name: "Zárate", parentId: 10 }]);
  });
});
