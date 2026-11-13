import { describe, expect, it } from "vitest";
import { parseSiteUrl } from "../src/lib/env";

describe("parseSiteUrl", () => {
  it("accepts https and returns only the origin", () => {
    expect(parseSiteUrl("https://faro.example/ruta?x=1")).toBe("https://faro.example");
    expect(parseSiteUrl(" http://localhost:3000/ ")).toBe("http://localhost:3000");
  });

  it("refuses http on a public host, junk and missing values", () => {
    for (const bad of ["http://faro.example", "faro.example", "//faro.example", "javascript:alert(1)", "", undefined]) {
      expect(() => parseSiteUrl(bad)).toThrow(/NEXT_PUBLIC_SITE_URL/);
    }
  });
});
