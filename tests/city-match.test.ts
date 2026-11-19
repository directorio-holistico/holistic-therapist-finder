import { describe, expect, it } from "vitest";
import { findExistingCity } from "@/lib/city-match";

const options = [
  { id: 1, name: "Cádiz" },
  { id: 2, name: "San Fernando" },
  { id: 3, name: "Jerez de la Frontera" },
];

describe("findExistingCity", () => {
  it("finds a city ignoring accents and capitals", () => {
    expect(findExistingCity(options, "cadiz")?.id).toBe(1);
    expect(findExistingCity(options, "CÁDIZ")?.id).toBe(1);
  });
  it("ignores extra spaces", () => {
    expect(findExistingCity(options, "  san   fernando ")?.id).toBe(2);
  });
  it("never matches a part of a name", () => {
    expect(findExistingCity(options, "Jerez")).toBeNull();
    expect(findExistingCity(options, "Cad")).toBeNull();
  });
  it("returns null for empty text or an empty list", () => {
    expect(findExistingCity(options, "   ")).toBeNull();
    expect(findExistingCity([], "Cádiz")).toBeNull();
  });
  it("does not guess when two cities share the name", () => {
    expect(findExistingCity([{ id: 1, name: "Córdoba" }, { id: 2, name: "cordoba" }], "Córdoba")).toBeNull();
  });
});
