import { describe, expect, it } from "vitest";
import { titleCaseName } from "@/lib/name-case";
import { readProfileForm } from "@/lib/profile-form";

describe("titleCaseName", () => {
  it("puts a capital only on the first letter of each name / mayúscula solo en la primera letra de cada nombre", () => {
    expect(titleCaseName("LILIANA GARCIA SERRANO")).toBe("Liliana Garcia Serrano");
    expect(titleCaseName("liliana garcia serrano")).toBe("Liliana Garcia Serrano");
    expect(titleCaseName("KaRiNa BuZzuRrO")).toBe("Karina Buzzurro");
    expect(titleCaseName("  Eduardo   Ariel  Vega ")).toBe("Eduardo Ariel Vega");
  });
  it("keeps accents and handles hyphens, apostrophes and initials / respeta tildes, guiones, apóstrofos e iniciales", () => {
    expect(titleCaseName("MARÍA JOSÉ ÁNGELES")).toBe("María José Ángeles");
    expect(titleCaseName("ana-laura d'angelo")).toBe("Ana-Laura D'Angelo");
    expect(titleCaseName("ARIEL j.p. vega")).toBe("Ariel J.P. Vega");
  });
  it("puts a capital after an opening parenthesis / mayúscula después de un paréntesis de apertura", () => {
    expect(titleCaseName("seva keval (matias duran)")).toBe("Seva Keval (Matias Duran)");
    expect(titleCaseName("SEVA KEVAL (MATÍAS DURAN)")).toBe("Seva Keval (Matías Duran)");
    expect(titleCaseName("Seva Keval (matías Duran)")).toBe("Seva Keval (Matías Duran)");
    expect(titleCaseName(titleCaseName("seva keval (matias duran)"))).toBe("Seva Keval (Matias Duran)");
  });
  it("keeps the linking words in lower case, except at the start / las palabras de enlace en minúscula, salvo al comienzo", () => {
    expect(titleCaseName("MARIA DE LOS ANGELES PEREZ Y GOMEZ")).toBe("Maria de los Angeles Perez y Gomez");
    expect(titleCaseName("DE LA CRUZ")).toBe("De la Cruz");
    expect(titleCaseName("diego ernesto di tillio")).toBe("Diego Ernesto Di Tillio");
  });
  it("is stable and survives empty text / es estable y soporta texto vacío", () => {
    expect(titleCaseName(titleCaseName("LILIANA GARCIA"))).toBe("Liliana Garcia");
    expect(titleCaseName("   ")).toBe("");
  });
});

describe("the profile form saves the name with that rule / el formulario guarda el nombre con esa regla", () => {
  const form = (displayName: string) => {
    const data = new FormData();
    data.set("displayName", displayName);
    data.set("cityId", "7");
    data.append("languages", "1");
    data.append("serviceModes_0", "1");
    data.append("sessionFormats_0", "1");
    data.set("phone", "+54 299 555 0101");
    data.set("therapyId_0", "10");
    return data;
  };
  it("normalizes an all-capitals name / normaliza un nombre todo en mayúsculas", () => {
    const parsed = readProfileForm(form("  LILIANA   GARCIA SERRANO "), 2026);
    expect(parsed.success && parsed.data.displayName).toBe("Liliana Garcia Serrano");
  });
});
