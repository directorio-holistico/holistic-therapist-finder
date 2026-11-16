import { describe, expect, it } from "vitest";
import { starRingGradient, STAR_DOT_COLORS } from "@/lib/brand";
import { capItems, initialsOf } from "@/lib/card-view";

describe("initialsOf", () => {
  it("takes two initials and ignores the [DEMO] tag", () => {
    expect(initialsOf("[DEMO] Iván Castellanos")).toBe("IC");
    expect(initialsOf("Eduardo Ariel Vega")).toBe("EA");
  });
  it("handles one word, accents, extra spaces and empty names", () => {
    expect(initialsOf("  marta  ")).toBe("M");
    expect(initialsOf("Álvaro")).toBe("Á");
    expect(initialsOf("")).toBe("?");
    expect(initialsOf("[DEMO]")).toBe("?");
    expect(initialsOf("123 456")).toBe("?");
  });
});

describe("capItems", () => {
  it("shows up to the limit and counts the rest", () => {
    expect(capItems(["a", "b", "c", "d", "e"], 3)).toEqual({ shown: ["a", "b", "c"], hidden: 2 });
    expect(capItems(["a", "b"], 3)).toEqual({ shown: ["a", "b"], hidden: 0 });
    expect(capItems([], 3)).toEqual({ shown: [], hidden: 0 });
  });
  it("never goes negative", () => {
    expect(capItems(["a"], -2)).toEqual({ shown: [], hidden: 1 });
  });
});

describe("starRingGradient", () => {
  it("has one hard stop per star colour, covering the full circle", () => {
    const g = starRingGradient();
    expect(g.startsWith("conic-gradient(")).toBe(true);
    for (const c of STAR_DOT_COLORS) expect(g).toContain(c);
    expect(g).toContain("330deg 360deg");
  });
});
