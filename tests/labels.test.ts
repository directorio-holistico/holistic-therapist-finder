import { describe, expect, it } from "vitest";
import { groupHeading, searchGroupTitle, terapeutasCount } from "@/lib/labels";

describe("searchGroupTitle", () => {
  it("says \"En tu zona\" only when a region or a city was chosen / dice \"En tu zona\" solo si se eligió región o ciudad", () => {
    expect(searchGroupTitle(1, true)).toBe("En tu zona");
    expect(searchGroupTitle(1, false)).toBe("Resultados");
  });
  it("leaves the remote groups as they are / deja igual los grupos a distancia", () => {
    expect(searchGroupTitle(2, false)).toBe("Atienden a distancia en tu país");
    expect(searchGroupTitle(3, true)).toBe("Atienden a distancia desde otros países");
  });
  it("an unknown group has no title / un grupo desconocido no tiene título", () => {
    expect(searchGroupTitle(9, true)).toBe("");
  });
});

describe("counts in the group headings / cantidades en los títulos de grupo", () => {
  it("uses singular and plural / singular y plural", () => {
    expect(terapeutasCount(1)).toBe("1 terapeuta");
    expect(terapeutasCount(2)).toBe("2 terapeutas");
    expect(terapeutasCount(0)).toBe("0 terapeutas");
  });
  it("puts the count right after the title / pone la cantidad pegada al título", () => {
    expect(groupHeading("En tu zona", 1)).toBe("En tu zona · 1 terapeuta");
    expect(groupHeading("Atienden a distancia en tu país", 3)).toBe("Atienden a distancia en tu país · 3 terapeutas");
    expect(groupHeading("", 2)).toBe("2 terapeutas");
  });
});
