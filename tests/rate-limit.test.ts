import { describe, expect, it, vi } from "vitest";
import { originHash } from "../src/lib/origin";
import { checkOriginLimit, limitMessage, resolveOrigin, type LimitDeps } from "../src/lib/rate-limit";

const KEY = "k".repeat(40);
const headers = (value?: string) => new Headers(value ? { "x-forwarded-for": value } : {});

function deps(overrides: Partial<LimitDeps> = {}): LimitDeps & { call: ReturnType<typeof vi.fn> } {
  return {
    hmacKey: () => KEY,
    allowMissingAddress: false,
    call: vi.fn(async () => ({ ok: true as const, allowed: true })),
    ...overrides,
  } as LimitDeps & { call: ReturnType<typeof vi.fn> };
}

describe("resolveOrigin", () => {
  it("hashes the address per action and never exposes it", () => {
    const login = resolveOrigin("login", headers("190.1.2.3"), deps());
    const link = resolveOrigin("login_link", headers("190.1.2.3"), deps());
    expect(login).toEqual({ ok: true, hash: originHash("190.1.2.3", KEY, "login") });
    expect(login.ok && login.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(login.ok && link.ok && login.hash !== link.hash).toBe(true); // one counter per action
    expect(JSON.stringify(login)).not.toContain("190");
  });
  it("has no origin without an address, except in development", () => {
    expect(resolveOrigin("login", headers(), deps())).toEqual({ ok: false, reason: "no_origin" });
    expect(resolveOrigin("login", headers("no es una ip"), deps())).toEqual({ ok: false, reason: "no_origin" });
    expect(resolveOrigin("login", headers(), deps({ allowMissingAddress: true })).ok).toBe(true);
  });
  it("reports an error (not a crash) when the secret is not available", () => {
    const broken = deps({ hmacKey: () => { throw new Error("falta"); } });
    expect(resolveOrigin("login", headers("190.1.2.3"), broken)).toEqual({ ok: false, reason: "error" });
  });
});

describe("checkOriginLimit", () => {
  it("lets the action through when the database allows it, sending only action and hash", async () => {
    const d = deps();
    expect(await checkOriginLimit("login", headers("190.1.2.3"), d)).toBe("allowed");
    expect(d.call).toHaveBeenCalledTimes(1);
    const [action, hash] = d.call.mock.calls[0] as [string, string];
    expect(action).toBe("login");
    expect(hash).toBe(originHash("190.1.2.3", KEY, "login"));
  });
  it("blocks when the database says the limit was reached", async () => {
    const d = deps({ call: vi.fn(async () => ({ ok: true as const, allowed: false })) });
    expect(await checkOriginLimit("login_link", headers("190.1.2.3"), d)).toBe("blocked");
  });
  it("refuses (never skips the limit) when the limiter fails or throws", async () => {
    expect(await checkOriginLimit("login", headers("190.1.2.3"), deps({ call: vi.fn(async () => ({ ok: false as const })) }))).toBe("error");
    expect(await checkOriginLimit("login", headers("190.1.2.3"), deps({ call: vi.fn(async () => { throw new Error("red"); }) }))).toBe("error");
  });
  it("does not call the database when there is no origin", async () => {
    const d = deps();
    expect(await checkOriginLimit("login", headers(), d)).toBe("no_origin");
    expect(d.call).not.toHaveBeenCalled();
  });
});

describe("limitMessage", () => {
  it("has one message per case and none mentions accounts or e-mails", () => {
    expect(limitMessage("blocked")).toMatch(/más tarde/);
    expect(limitMessage("error")).toBe(limitMessage("no_origin"));
    for (const outcome of ["blocked", "error", "no_origin"] as const) expect(limitMessage(outcome)).not.toMatch(/mail|cuenta|contraseña/i);
  });
});
