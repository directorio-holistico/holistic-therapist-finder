import { describe, expect, it } from "vitest";
import { searchGroupTitle } from "@/lib/labels";

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
