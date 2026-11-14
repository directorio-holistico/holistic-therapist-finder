// The reveal, branch by branch, without network. / El revelado, rama por rama, sin red.
import { describe, expect, it, vi } from "vitest";
import { REVEAL_RESPONSES, revealContact, type RevealDeps } from "../src/lib/reveal";

const ID = "20000000-0000-0000-0000-0000000029a1";
const headers = new Headers({ "x-forwarded-for": "190.1.2.3" });

function deps(overrides: Partial<RevealDeps> = {}) {
  const verify = vi.fn().mockResolvedValue({ ok: true });
  const callDatabase = vi.fn().mockResolvedValue({ ok: true, rows: [{ contact_type: "phone", value: "+54 298 4000000", accepts_whatsapp: true }] });
  return { verify, callDatabase, all: { hmacKey: () => "k".repeat(40), allowMissingAddress: false, verify, callDatabase, ...overrides } satisfies RevealDeps };
}

describe("revealContact", () => {
  it("reveals the contacts after Turnstile, with a 64-hex origin hash and no address", async () => {
    const d = deps();
    const outcome = await revealContact({ body: { profileId: ID, token: "tok" }, headers }, d.all);
    expect(outcome).toEqual({ status: "ok", contacts: [{ type: "phone", value: "+54 298 4000000", whatsapp: true }] });
    expect(d.verify).toHaveBeenCalledWith("tok", "190.1.2.3");
    const [profileId, hash] = d.callDatabase.mock.calls[0] as [string, string];
    expect(profileId).toBe(ID);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hash).not.toContain("190");
  });

  it("answers with an empty list when there is nothing to reveal", async () => {
    const d = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: true, rows: [] }) });
    expect(await revealContact({ body: { profileId: ID, token: "tok" }, headers }, d.all)).toEqual({ status: "ok", contacts: [] });
  });

  it("refuses a bad request without touching Turnstile or the database", async () => {
    const d = deps();
    for (const body of [null, {}, { profileId: "x", token: "tok" }, { profileId: ID }, { profileId: ID, token: "" }, { profileId: ID, token: "x".repeat(2049) }]) {
      expect((await revealContact({ body, headers }, d.all)).status).toBe("bad_request");
    }
    expect(d.verify).not.toHaveBeenCalled();
    expect(d.callDatabase).not.toHaveBeenCalled();
  });

  it("refuses when there is no address on the real site, but lets a local run through", async () => {
    const d = deps();
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers: new Headers() }, d.all)).status).toBe("no_origin");
    expect(d.verify).not.toHaveBeenCalled();

    const local = deps({ allowMissingAddress: true });
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers: new Headers() }, local.all)).status).toBe("ok");
    expect(local.verify).toHaveBeenCalledWith("tok", null);
  });

  it("does not reveal or count when Turnstile fails", async () => {
    const failed = deps({ verify: vi.fn().mockResolvedValue({ ok: false, reason: "invalid" }) });
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers }, failed.all)).status).toBe("captcha_failed");
    expect(failed.callDatabase).not.toHaveBeenCalled();

    const down = deps({ verify: vi.fn().mockResolvedValue({ ok: false, reason: "unavailable" }) });
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers }, down.all)).status).toBe("captcha_unavailable");
    expect(down.callDatabase).not.toHaveBeenCalled();
  });

  it("tells the limit apart from any other database error", async () => {
    const limit = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: false, code: "RL429" }) });
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers }, limit.all)).status).toBe("rate_limited");
    const other = deps({ callDatabase: vi.fn().mockResolvedValue({ ok: false, code: "XX000" }) });
    expect((await revealContact({ body: { profileId: ID, token: "tok" }, headers }, other.all)).status).toBe("error");
  });

  it("uses the same hash for the same address and another for another address", async () => {
    const a = deps();
    const b = deps();
    await revealContact({ body: { profileId: ID, token: "t" }, headers }, a.all);
    await revealContact({ body: { profileId: ID, token: "t" }, headers: new Headers({ "x-forwarded-for": "190.1.2.4" }) }, b.all);
    expect((a.callDatabase.mock.calls[0] as string[])[1]).not.toBe((b.callDatabase.mock.calls[0] as string[])[1]);
  });
});

describe("REVEAL_RESPONSES", () => {
  it("has a visitor message and an HTTP code for every failure", () => {
    expect(REVEAL_RESPONSES.rate_limited.http).toBe(429);
    expect(REVEAL_RESPONSES.captcha_failed.http).toBe(403);
    expect(REVEAL_RESPONSES.captcha_unavailable.http).toBe(503);
    for (const value of Object.values(REVEAL_RESPONSES)) expect(value.message.length).toBeGreaterThan(10);
  });
});
