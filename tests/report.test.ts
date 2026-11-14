// Reporting a profile, branch by branch, without network. / Denunciar un perfil, rama por rama, sin red.
import { describe, expect, it, vi } from "vitest";
import { originHash } from "../src/lib/origin";
import { REPORT_RESPONSES, reportProfile, type ReportDeps } from "../src/lib/report";

const ID = "20000000-0000-0000-0000-0000000070a1";
const headers = new Headers({ "x-forwarded-for": "190.1.2.3" });
const body = { profileId: ID, reason: "cure_claim", details: "  Promete curar  ", email: " Ana@Example.TEST ", token: "tok" };

function deps(overrides: Partial<ReportDeps> = {}) {
  const verify = vi.fn().mockResolvedValue({ ok: true });
  const callDatabase = vi.fn().mockResolvedValue({ ok: true });
  return { verify, callDatabase, all: { hmacKey: () => "k".repeat(40), allowMissingAddress: false, verify, callDatabase, ...overrides } satisfies ReportDeps };
}

describe("reportProfile", () => {
  it("creates the report after Turnstile, with clean fields and a 64-hex origin hash that has no address", async () => {
    const d = deps();
    expect(await reportProfile({ body, headers }, d.all)).toEqual({ status: "ok" });
    expect(d.verify).toHaveBeenCalledWith("tok", "190.1.2.3");
    const [report, hash] = d.callDatabase.mock.calls[0] as [Record<string, string>, string];
    expect(report).toEqual({ profileId: ID, reason: "cure_claim", details: "Promete curar", email: "ana@example.test" });
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hash).not.toContain("190");
  });

  it("uses a different hash for a report than for a reveal of the same visitor", () => {
    const key = "k".repeat(40);
    expect(originHash("190.1.2.3", key, "report")).not.toBe(originHash("190.1.2.3", key, "reveal"));
    expect(originHash("190.1.2.3", key)).toBe(originHash("190.1.2.3", key, "reveal"));
  });

  it("accepts a report with no details and no mail, and sends them empty", async () => {
    const d = deps();
    expect((await reportProfile({ body: { profileId: ID, reason: "other", token: "tok" }, headers }, d.all)).status).toBe("ok");
    expect(d.callDatabase.mock.calls[0]?.[0]).toEqual({ profileId: ID, reason: "other", details: "", email: "" });
    expect((await reportProfile({ body: { ...body, details: "   ", email: "  " }, headers }, d.all)).status).toBe("ok");
    expect(d.callDatabase.mock.calls[1]?.[0]).toMatchObject({ details: "", email: "" });
  });

  it("refuses a bad request without touching Turnstile or the database", async () => {
    const d = deps();
    const bad = [
      null, {}, { ...body, profileId: "x" }, { ...body, reason: undefined }, { ...body, reason: "inventado" }, { ...body, reason: "" },
      { ...body, details: "x".repeat(1001) }, { ...body, email: "sin-arroba" }, { ...body, email: `${"a".repeat(250)}@x.co` },
      { ...body, token: "" }, { ...body, token: "x".repeat(2049) }, { ...body, details: 5 }, { ...body, email: null },
    ];
    for (const candidate of bad) expect((await reportProfile({ body: candidate, headers }, d.all)).status).toBe("bad_request");
    expect(d.verify).not.toHaveBeenCalled();
    expect(d.callDatabase).not.toHaveBeenCalled();
  });

  it("accepts a detail of exactly 1000 characters", async () => {
    const d = deps();
    expect((await reportProfile({ body: { ...body, details: "y".repeat(1000) }, headers }, d.all)).status).toBe("ok");
  });

  it("refuses when there is no address on the real site, but lets a local run through", async () => {
    const d = deps();
    expect((await reportProfile({ body, headers: new Headers() }, d.all)).status).toBe("no_origin");
    expect(d.verify).not.toHaveBeenCalled();
    const local = deps({ allowMissingAddress: true });
    expect((await reportProfile({ body, headers: new Headers() }, local.all)).status).toBe("ok");
    expect(local.verify).toHaveBeenCalledWith("tok", null);
  });

  it("does not create or count anything when Turnstile fails or is down", async () => {
    const failed = deps({ verify: vi.fn().mockResolvedValue({ ok: false, reason: "failed" }) });
    expect((await reportProfile({ body, headers }, failed.all)).status).toBe("captcha_failed");
    const down = deps({ verify: vi.fn().mockResolvedValue({ ok: false, reason: "unavailable" }) });
    expect((await reportProfile({ body, headers }, down.all)).status).toBe("captcha_unavailable");
    expect(failed.callDatabase).not.toHaveBeenCalled();
    expect(down.callDatabase).not.toHaveBeenCalled();
  });

  it("maps the database answers: limit, invalid data, anything else", async () => {
    const limit = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: false, code: "RL429" }) });
    expect((await reportProfile({ body, headers }, limit.all)).status).toBe("rate_limited");
    const invalid = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: false, code: "22023" }) });
    expect((await reportProfile({ body, headers }, invalid.all)).status).toBe("invalid");
    for (const code of ["42501", "23514", null]) {
      const other = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: false, code }) });
      expect((await reportProfile({ body, headers }, other.all)).status).toBe("error");
    }
  });

  it("never tells the visitor why a profile was refused, and no message carries internal detail", () => {
    for (const { message } of Object.values(REPORT_RESPONSES)) {
      expect(message).not.toMatch(/22023|RL429|rate_limit|supabase|service|hash|turnstile secret/i);
    }
    expect(REPORT_RESPONSES.invalid.message).toMatch(/ya no está disponible o los datos no son válidos/);
  });
});
