// Type-ahead filter of the long option lists. / Filtro por escritura de las listas largas de opciones.

import { describe, expect, it } from "vitest";
import { filterOptions, isFiltering, normalizeText } from "@/lib/option-filter";

const OPTIONS = [
  { id: 1, name: "LNT® Schwiderski" },
  { id: 2, name: "Masaje con calor y elementos" },
  { id: 3, name: "Masaje descontracturante" },
  { id: 4, name: "Reflexología" },
  { id: 5, name: "Terapia vibracional" },
  { id: 6, name: "Facilitador de procesos sociales" },
  { id: 7, name: "Acupuntura (Medicina Tradicional China)" },
];
const idsOf = (query: string) => filterOptions(OPTIONS, query).map((option) => option.id);

describe("normalizeText", () => {
  it("drops accents and capitals / saca tildes y mayúsculas", () => {
    expect(normalizeText("Reflexología")).toBe("reflexologia");
    expect(normalizeText("MEDICINA")).toBe("medicina");
  });
});

describe("isFiltering", () => {
  it("needs 3 letters, ignoring spaces at the ends / pide 3 letras, sin contar espacios de los extremos", () => {
    expect(isFiltering("")).toBe(false);
    expect(isFiltering("ma")).toBe(false);
    expect(isFiltering("  ma  ")).toBe(false);
    expect(isFiltering("mas")).toBe(true);
  });
});

describe("filterOptions", () => {
  it("shows everything with fewer than 3 letters / muestra todo con menos de 3 letras", () => {
    expect(idsOf("")).toHaveLength(OPTIONS.length);
    expect(idsOf("ma")).toHaveLength(OPTIONS.length);
  });

  it("finds a therapy by the beginning of its words / encuentra una terapia por el comienzo de sus palabras", () => {
    expect(idsOf("mas cal")).toEqual([2]);
    expect(idsOf("cal mas")).toEqual([2]);
  });

  it("filters from 3 letters / filtra desde 3 letras", () => {
    expect(idsOf("mas")).toEqual([2, 3]);
  });

  it("ignores accents and capitals in both sides / ignora tildes y mayúsculas de los dos lados", () => {
    expect(idsOf("REFLEXOLOGIA")).toEqual([4]);
    expect(idsOf("acupuntura medicina")).toEqual([7]);
  });

  it("matches words inside parentheses and after symbols / encuentra palabras entre paréntesis y tras símbolos", () => {
    expect(idsOf("tradicional")).toEqual([7]);
    expect(idsOf("lnt")).toEqual([1]);
  });

  it("does not match the middle of a word / no encuentra el medio de una palabra", () => {
    expect(idsOf("alor")).toEqual([]);
  });

  it("returns nothing when no option matches / no devuelve nada si ninguna coincide", () => {
    expect(idsOf("xyz")).toEqual([]);
  });

  it("keeps the catalog order / mantiene el orden del catálogo", () => {
    expect(idsOf("ter")).toEqual([5]);
    expect(idsOf("pro soc")).toEqual([6]);
  });
});
