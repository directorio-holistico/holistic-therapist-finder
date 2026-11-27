import { describe, expect, it } from "vitest";
import { starRingGradient, STAR_DOT_COLORS } from "@/lib/brand";
import { capItems, flagSrc, initialsOf } from "@/lib/card-view";

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

describe("flagSrc", () => {
  it("returns the file of each launch country, whatever the case or spaces", () => {
    expect(flagSrc("AR")).toBe("/flags/ar.svg");
    expect(flagSrc(" mx ")).toBe("/flags/mx.svg");
    expect(flagSrc("es")).toBe("/flags/es.svg");
    expect(flagSrc("cl")).toBe("/flags/cl.svg");
    expect(flagSrc("uy")).toBe("/flags/uy.svg");
  });
  it("returns null when there is no flag, instead of building a path", () => {
    expect(flagSrc("BR")).toBeNull();
    expect(flagSrc("../x")).toBeNull();
    expect(flagSrc("")).toBeNull();
    expect(flagSrc(null)).toBeNull();
    expect(flagSrc(undefined)).toBeNull();
  });
});
