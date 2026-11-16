import { runInNewContext } from "node:vm";
import { describe, expect, it } from "vitest";
import { parseTheme, THEME_INIT_SCRIPT, THEME_STORAGE_KEY } from "@/lib/theme";

function runScript(getItem: () => string | null) {
  const attributes: Record<string, string> = {};
  runInNewContext(THEME_INIT_SCRIPT, {
    window: { localStorage: { getItem } },
    document: { documentElement: { setAttribute: (k: string, v: string) => (attributes[k] = v) } },
  });
  return attributes["data-theme"];
}

describe("parseTheme", () => {
  it("defaults to light", () => {
    expect(parseTheme(null)).toBe("claro");
    expect(parseTheme(undefined)).toBe("claro");
    expect(parseTheme("")).toBe("claro");
    expect(parseTheme("dark")).toBe("claro");
    expect(parseTheme("OSCURO")).toBe("claro");
  });
  it("accepts only the exact dark value", () => {
    expect(parseTheme("oscuro")).toBe("oscuro");
  });
});

describe("THEME_INIT_SCRIPT", () => {
  it("uses the stored choice only when it is dark", () => {
    expect(runScript(() => "oscuro")).toBe("oscuro");
    expect(runScript(() => "claro")).toBe("claro");
    expect(runScript(() => "cualquier-cosa")).toBe("claro");
    expect(runScript(() => null)).toBe("claro");
  });
  it("stays light if storage is blocked", () => {
    expect(
      runScript(() => {
        throw new Error("blocked");
      }),
    ).toBe("claro");
  });
  it("reads the documented storage key", () => {
    let asked = "";
    runInNewContext(THEME_INIT_SCRIPT, {
      window: { localStorage: { getItem: (k: string) => ((asked = k), null) } },
      document: { documentElement: { setAttribute: () => undefined } },
    });
    expect(asked).toBe(THEME_STORAGE_KEY);
  });
});
