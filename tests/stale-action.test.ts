import { describe, expect, it } from "vitest";
import { runGuarded, STALE_MESSAGE } from "@/lib/stale-action";

const isStale = (error: unknown) => error instanceof Error && error.name === "Stale";

describe("runGuarded", () => {
  it("returns the result when the action works", async () => {
    expect(await runGuarded(async () => "ok", isStale, "stale")).toBe("ok");
  });

  it("returns the given result when the page is out of date", async () => {
    const old = new Error("old page");
    old.name = "Stale";
    expect(await runGuarded(async () => { throw old; }, isStale, "stale")).toBe("stale");
  });

  it("throws any other error again, untouched", async () => {
    await expect(runGuarded(async () => { throw new Error("boom"); }, isStale, "stale")).rejects.toThrow("boom");
  });

  it("has a message that tells the person what to do", () => {
    expect(STALE_MESSAGE).toContain("Recargar la página");
    expect(STALE_MESSAGE).toContain("borrador");
  });
});
