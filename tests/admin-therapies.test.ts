// What the admin screen that adds, hides and shows therapies accepts and explains. / Lo que acepta y explica la pantalla de admin de terapias.
import { describe, expect, it } from "vitest";
import {
  THERAPY_CODE_PATTERN, canDismissSuggestion, explainDismissError, explainTherapyError, parseNameParam, proposeTherapyCode, readAddTherapyForm, revisionStatusLabel, splitSuggestedTherapies,
} from "../src/lib/admin/therapy-admin";

function form(fields: Record<string, string>): FormData {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

describe("proposeTherapyCode", () => {
  it("makes a lowercase code without accents or symbols", () => {
    expect(proposeTherapyCode("Coaching transpersonal")).toBe("coaching_transpersonal");
    expect(proposeTherapyCode("Psicoanálisis y psicoterapia")).toBe("psicoanalisis_y_psicoterapia");
    expect(proposeTherapyCode("  LNT® - La Nueva Terapia ")).toBe("lnt_la_nueva_terapia");
  });
  it("never starts with a digit and never ends with an underscore", () => {
    expect(proposeTherapyCode("5 Ritmos")).toBe("t_5_ritmos");
    expect(proposeTherapyCode("Yoga!!!")).toBe("yoga");
  });
  it("returns an empty text when there is nothing usable, and respects the length limit", () => {
    expect(proposeTherapyCode("")).toBe("");
    expect(proposeTherapyCode("***")).toBe("");
    expect(proposeTherapyCode("a".repeat(100)).length).toBe(60);
  });
  it("always gives a code the database accepts (when long enough)", () => {
    for (const name of ["Reiki", "Terapia de vidas pasadas", "Ñandú y más", "7 chakras"]) {
      expect(THERAPY_CODE_PATTERN.test(proposeTherapyCode(name))).toBe(true);
    }
  });
});

describe("readAddTherapyForm", () => {
  it("accepts a complete form and cleans the spaces", () => {
    const parsed = readAddTherapyForm(form({ name: "  Coaching   transpersonal ", shortName: "", code: "coaching_transpersonal", active: "on" }));
    expect(parsed).toEqual({ ok: true, value: { name: "Coaching transpersonal", shortName: null, code: "coaching_transpersonal", active: true } });
  });
  it("keeps the short name when it is written, and reads an unticked box as hidden", () => {
    const parsed = readAddTherapyForm(form({ name: "Psicoanálisis y psicoterapia psicoanalítica", shortName: " Psicoanálisis ", code: "psychoanalysis" }));
    expect(parsed).toEqual({ ok: true, value: { name: "Psicoanálisis y psicoterapia psicoanalítica", shortName: "Psicoanálisis", code: "psychoanalysis", active: false } });
  });
  it("refuses an empty name, a long name, a long short name and a bad code", () => {
    expect(readAddTherapyForm(form({ name: "   ", code: "reiki", shortName: "" })).ok).toBe(false);
    expect(readAddTherapyForm(form({ name: "x".repeat(121), code: "reiki", shortName: "" })).ok).toBe(false);
    expect(readAddTherapyForm(form({ name: "Reiki", code: "reiki", shortName: "x".repeat(41) })).ok).toBe(false);
    for (const code of ["", "R", "Reiki", "con espacio", "1reiki", "reiki-2", "reikí", "a".repeat(61)]) {
      const parsed = readAddTherapyForm(form({ name: "Reiki", code, shortName: "" }));
      expect(parsed.ok).toBe(false);
    }
  });
  it("treats missing fields as empty instead of failing", () => {
    expect(readAddTherapyForm(new FormData()).ok).toBe(false);
  });
});

describe("explainTherapyError", () => {
  it("gives one message per refusal", () => {
    expect(explainTherapyError({ code: "42501" })).toContain("no sos administrador");
    expect(explainTherapyError({ code: "23505" })).toContain("Ya existe");
    expect(explainTherapyError({ code: "22023" })).toContain("no acepta");
    expect(explainTherapyError({ code: "P0002" })).toContain("No se encontró");
    expect(explainTherapyError({ code: "XX000" })).toContain("Probá de nuevo");
    expect(explainTherapyError({})).toContain("Probá de nuevo");
  });
});

describe("splitSuggestedTherapies", () => {
  it("splits by comma, trims and drops empty pieces", () => {
    expect(splitSuggestedTherapies("Coaching, Transpersonal ,, intrapersonal")).toEqual(["Coaching", "Transpersonal", "intrapersonal"]);
  });
  it("drops repeats ignoring accents and capitals", () => {
    expect(splitSuggestedTherapies("Reiki, reiki, REIKÍ")).toEqual(["Reiki"]);
  });
  it("returns nothing for an empty text", () => {
    expect(splitSuggestedTherapies("  ")).toEqual([]);
  });
});

describe("parseNameParam", () => {
  it("reads one text, trims it and cuts it to the limit", () => {
    expect(parseNameParam("  Coaching   transpersonal ")).toBe("Coaching transpersonal");
    expect(parseNameParam("x".repeat(500)).length).toBe(120);
  });
  it("takes the first value of a list and ignores anything else", () => {
    expect(parseNameParam(["Reiki", "Otra"])).toBe("Reiki");
    expect(parseNameParam(undefined)).toBe("");
    expect(parseNameParam([])).toBe("");
  });
});

describe("revisionStatusLabel", () => {
  it("names the known statuses and shows an unknown one as it is", () => {
    expect(revisionStatusLabel("approved")).toBe("Aprobada");
    expect(revisionStatusLabel("pending_review")).toBe("Esperando revisión");
    expect(revisionStatusLabel("otra")).toBe("otra");
  });
});

describe("dismissing a request", () => {
  it("allows it only for a decided revision", () => {
    for (const code of ["approved", "rejected", "discarded"]) expect(canDismissSuggestion(code)).toBe(true);
    for (const code of ["draft", "pending_review", "?", ""]) expect(canDismissSuggestion(code)).toBe(false);
  });
  it("explains each refusal", () => {
    expect(explainDismissError({ code: "42501" })).toContain("no sos administrador");
    expect(explainDismissError({ code: "55000" })).toContain("Primero decidí la revisión");
    expect(explainDismissError({ code: "P0002" })).toContain("ya no existe");
    expect(explainDismissError({ code: "22023" })).toContain("inválido");
    expect(explainDismissError({})).toContain("Probá de nuevo");
  });
});
