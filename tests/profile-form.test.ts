import { describe, expect, it } from "vitest";
import { buildChildOptions } from "@/lib/catalogs";
import {
  buildPayload, defaultsFromPayload, EMPTY_DEFAULTS, instagramIsValid, normalizeInstagram, normalizeSocialLink, parseAmount, phoneIsValid, readProfileForm, socialLinkIsValid,
} from "@/lib/profile-form";

const YEAR = 2026;
const TYPES = { phone: 1, email: 2, website: 3, instagram: 4, facebook: 5, tiktok: 6, youtube: 7 };
const AUD = { own: 1, other: 2 };
const CURRENCIES = new Map([[1, 2], [2, 0]]); // 1 = ARS (2 decimals), 2 = CLP (0 decimals)

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
  // modes and formats belong to EACH therapy (row 0 here) / modalidades y formatos son de CADA terapia (acá la fila 0)
  serviceModes_0: ["1", "2"],
  sessionFormats_0: ["1"],
  phone: "+54 299 555 0101",
  therapyId_0: "10",
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

  it("requires name, phone, a city, a language, and for the therapy a mode and a format", () => {
    for (const missing of ["displayName", "phone", "cityId", "languages", "serviceModes_0", "sessionFormats_0", "therapyId_0"]) {
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
    if (ok.success) expect(buildPayload(ok.data, TYPES, AUD).location_id).toBeNull();
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
    expect(buildPayload(ok.data, TYPES, AUD).contacts.at(-1)).toEqual({ contact_type_id: 4, value: "ana.terapias", accepts_whatsapp: false });
    expect(readProfileForm(form({ ...VALID, instagram: "no valido!" }), YEAR).success).toBe(false);
  });
});

describe("facebook, tiktok and youtube", () => {
  it("rebuilds a clean https link from a link, a link without scheme or a user name", () => {
    expect(normalizeSocialLink("facebook", "anaterapias")).toBe("https://www.facebook.com/anaterapias");
    expect(normalizeSocialLink("facebook", "http://WWW.Facebook.com/AnaTerapias/?fbclid=abc#x")).toBe("https://www.facebook.com/AnaTerapias/");
    expect(normalizeSocialLink("facebook", "facebook.com/profile.php?id=123&ref=x")).toBe("https://facebook.com/profile.php?id=123&ref=x");
    expect(normalizeSocialLink("tiktok", "@Ana.Terapias")).toBe("https://www.tiktok.com/@Ana.Terapias");
    expect(normalizeSocialLink("tiktok", "https://www.tiktok.com/@ana.terapias?lang=es")).toBe("https://www.tiktok.com/@ana.terapias");
    expect(normalizeSocialLink("youtube", "@anaterapias")).toBe("https://www.youtube.com/@anaterapias");
    expect(normalizeSocialLink("youtube", "youtube.com/@anaterapias/")).toBe("https://youtube.com/@anaterapias/");
    expect(normalizeSocialLink("youtube", "   ")).toBe("");
  });

  it("accepts only the profile pages of those sites", () => {
    expect(socialLinkIsValid("facebook", "https://www.facebook.com/anaterapias")).toBe(true);
    expect(socialLinkIsValid("tiktok", "https://www.tiktok.com/@ana.terapias")).toBe(true);
    expect(socialLinkIsValid("youtube", "https://www.youtube.com/@anaterapias")).toBe(true);
    expect(socialLinkIsValid("youtube", "https://www.youtube.com/channel/UC1234567890123456789012")).toBe(true);
    // other sites, look-alike hosts, user-info tricks, plain http, videos, spaces
    for (const bad of [
      "https://facebook.com.evil.test/x", "https://evil.test/facebook.com/x", "https://facebook.com@evil.test/x", "http://www.facebook.com/x",
      "https://www.facebook.com/", "https://facebook.com/a b",
    ]) expect(socialLinkIsValid("facebook", bad), bad).toBe(false);
    for (const bad of ["https://www.tiktok.com/@a", "https://www.tiktok.com/@ana/video/123", "https://vm.tiktok.com/abc", "https://tiktok.com.evil.test/@ana"]) {
      expect(socialLinkIsValid("tiktok", bad), bad).toBe(false);
    }
    for (const bad of ["https://www.youtube.com/watch?v=abc", "https://youtu.be/abc", "https://www.youtube.com/@ab", "https://youtube.com.evil.test/@ana"]) {
      expect(socialLinkIsValid("youtube", bad), bad).toBe(false);
    }
  });

  it("are optional, become public contacts and reject other sites or text with spaces", () => {
    const none = readProfileForm(form(VALID), YEAR);
    expect(none.success && [none.data.facebook, none.data.tiktok, none.data.youtube]).toEqual([null, null, null]);
    const ok = readProfileForm(form({ ...VALID, facebook: "anaterapias", tiktok: "@ana.terapias", youtube: "@anaterapias" }), YEAR);
    if (!ok.success) throw new Error("must parse");
    expect(buildPayload(ok.data, TYPES, AUD).contacts.slice(1)).toEqual([
      { contact_type_id: 5, value: "https://www.facebook.com/anaterapias", accepts_whatsapp: false },
      { contact_type_id: 6, value: "https://www.tiktok.com/@ana.terapias", accepts_whatsapp: false },
      { contact_type_id: 7, value: "https://www.youtube.com/@anaterapias", accepts_whatsapp: false },
    ]);
    expect(readProfileForm(form({ ...VALID, facebook: "https://evil.test/anaterapias" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, tiktok: "ana terapias" }), YEAR).success).toBe(false);
    expect(readProfileForm(form({ ...VALID, youtube: "https://www.youtube.com/watch?v=abc" }), YEAR).success).toBe(false);
  });
});

describe("therapies and rates", () => {
  const withTherapies = (fields: Record<string, string | string[]>) => readProfileForm(form({ ...VALID, ...fields }), YEAR, CURRENCIES);

  it("reads amounts the way people write them", () => {
    expect(parseAmount("15000")).toBe(15000);
    expect(parseAmount("15.000")).toBe(15000);
    expect(parseAmount("15.000,50")).toBe(15000.5);
    expect(parseAmount("15000,5")).toBe(15000.5);
    expect(parseAmount("15.5")).toBe(15.5);
    expect(parseAmount("  ")).toBeNull();
    for (const bad of ["abc", "15 mil", "-5", "1,2,3", "12.34.56", "$100"]) expect(parseAmount(bad), bad).toBeNaN();
  });

  it("needs at least one therapy and drops the empty rows", () => {
    const none = withTherapies({ therapyId_0: "" });
    expect(none.success).toBe(false);
    const ok = withTherapies({ therapyId_1: "11", minutes_1: "60", serviceModes_1: ["1"], sessionFormats_1: ["2"] });
    expect(ok.success && ok.data.therapies).toEqual([
      { therapyId: 10, minutes: null, rateOwn: null, rateOther: null, serviceModes: [1, 2], sessionFormats: [1] },
      { therapyId: 11, minutes: 60, rateOwn: null, rateOther: null, serviceModes: [1], sessionFormats: [2] },
    ]);
  });

  it("rejects half filled rows, repeated therapies and bad durations", () => {
    expect(withTherapies({ therapyId_1: "", minutes_1: "30" }).success).toBe(false);
    expect(withTherapies({ therapyId_1: "10" }).success).toBe(false);
    for (const minutes of ["4", "481", "abc", "1.5"]) expect(withTherapies({ minutes_0: minutes }).success, minutes).toBe(false);
    expect(withTherapies({ minutes_0: "5" }).success && withTherapies({ minutes_0: "480" }).success).toBe(true);
  });

  it("needs at least one mode and one format for EACH therapy, and keeps each therapy's own lists", () => {
    const message = (fields: Record<string, string | string[]>) => {
      const parsed = withTherapies(fields);
      return parsed.success ? null : parsed.error.issues[0]?.message ?? "";
    };
    expect(message({ therapyId_1: "11" })).toMatch(/Terapia 2.*modalidad/);
    expect(message({ therapyId_1: "11", serviceModes_1: ["1"] })).toMatch(/Terapia 2.*formato/);
    expect(message({ therapyId_1: "11", sessionFormats_1: ["1"] })).toMatch(/Terapia 2.*modalidad/);
    // modes ticked in a row without a therapy: the row is not empty, so it must be fixed or cleared / modalidad sin terapia: la fila no está vacía
    expect(message({ therapyId_1: "", serviceModes_1: ["1"] })).toMatch(/Terapia 2.*elegí la terapia/);
    // one therapy in person, another remote only / una terapia presencial, otra solo a distancia
    const parsed = withTherapies({ therapyId_0: "10", serviceModes_0: ["1"], sessionFormats_0: ["1"], therapyId_1: "11", serviceModes_1: ["2"], sessionFormats_1: ["1", "2"] });
    expect(parsed.success && parsed.data.therapies.map((slot) => [slot.serviceModes, slot.sessionFormats])).toEqual([[[1], [1]], [[2], [1, 2]]]);
  });

  it("needs a currency for any rate, and respects its decimals", () => {
    expect(withTherapies({ rateOwn_0: "15000" }).success).toBe(false);
    expect(withTherapies({ rateOwn_0: "15000", currencyOwn: "9" }).success).toBe(false);
    expect(withTherapies({ rateOwn_0: "15000,50", currencyOwn: "1" }).success).toBe(true);
    expect(withTherapies({ rateOwn_0: "15000,50", currencyOwn: "2" }).success).toBe(false);
    expect(withTherapies({ rateOwn_0: "0", currencyOwn: "1" }).success).toBe(false);
    expect(withTherapies({ rateOwn_0: "100000001", currencyOwn: "1" }).success).toBe(false);
    // a currency without any amount is simply ignored / una moneda sin montos se ignora
    const ignored = withTherapies({ currencyOwn: "1" });
    expect(ignored.success && ignored.data.currencyOwn).toBeNull();
  });

  it("builds the payload the database expects and refills the form from it", () => {
    const parsed = withTherapies({
      minutes_0: "60", rateOwn_0: "15.000", rateOther_0: "40", currencyOwn: "1", currencyOther: "1",
      therapyId_1: "11", rateOwn_1: "9000", serviceModes_1: ["2"], sessionFormats_1: ["2", "1", "2"],
    });
    if (!parsed.success) throw new Error("must parse");
    const payload = buildPayload(parsed.data, TYPES, AUD);
    expect(payload.therapies).toEqual([
      {
        therapy_id: 10, session_minutes: 60, service_modes: [1, 2], session_formats: [1],
        rates: [{ rate_audience_id: 1, amount: 15000, currency_id: 1 }, { rate_audience_id: 2, amount: 40, currency_id: 1 }],
      },
      { therapy_id: 11, session_minutes: null, service_modes: [2], session_formats: [1, 2], rates: [{ rate_audience_id: 1, amount: 9000, currency_id: 1 }] },
    ]);
    const back = defaultsFromPayload(payload, TYPES, AUD);
    expect(back.therapies).toHaveLength(4);
    expect(back.therapies[0]).toEqual({ therapyId: 10, minutes: "60", rateOwn: "15000", rateOther: "40", serviceModes: [1, 2], sessionFormats: [1] });
    expect(back.therapies[1]).toMatchObject({ therapyId: 11, serviceModes: [2], sessionFormats: [1, 2] });
    expect(back.therapies[2]).toEqual({ therapyId: null, minutes: "", rateOwn: "", rateOther: "", serviceModes: [], sessionFormats: [] });
    expect(back.currencyOwn).toBe(1);
    expect(back.currencyOther).toBe(1);
  });
});

describe("payload", () => {
  it("uses only the keys the database knows and puts the phone first", () => {
    const parsed = readProfileForm(form({ ...VALID, email: "a@b.co", phoneWhatsapp: "on", languages: ["2", "1", "2"] }), YEAR);
    if (!parsed.success) throw new Error("must parse");
    const payload = buildPayload(parsed.data, TYPES, AUD);
    expect(Object.keys(payload).sort()).toEqual([
      "contacts", "display_name", "headline", "languages", "location_id", "practice_start_year", "therapies", "zone",
    ]);
    // the modes and formats travel INSIDE each therapy, never at the profile level / viajan DENTRO de cada terapia, nunca a nivel perfil
    expect(Object.keys(payload.therapies[0] ?? {}).sort()).toEqual(["rates", "service_modes", "session_formats", "session_minutes", "therapy_id"]);
    expect(payload.languages).toEqual([1, 2]);
    expect(payload.contacts).toEqual([
      { contact_type_id: 1, value: "+54 299 555 0101", accepts_whatsapp: true },
      { contact_type_id: 2, value: "a@b.co", accepts_whatsapp: false },
    ]);
  });

  it("round-trips through defaultsFromPayload and survives garbage", () => {
    const parsed = readProfileForm(form({ ...VALID, headline: "Hola", zone: "Centro", practiceStartYear: "2015" }), YEAR);
    if (!parsed.success) throw new Error("must parse");
    const back = defaultsFromPayload(buildPayload(parsed.data, TYPES, AUD), TYPES, AUD);
    expect(back).toMatchObject({ displayName: "Lucía Ferrante", headline: "Hola", zone: "Centro", practiceStartYear: "2015", cityId: 7, phone: "+54 299 555 0101" });
    expect(defaultsFromPayload("basura", TYPES, AUD)).toEqual(EMPTY_DEFAULTS);
    expect(defaultsFromPayload({ languages: "no" }, TYPES, AUD)).toEqual(EMPTY_DEFAULTS);
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
