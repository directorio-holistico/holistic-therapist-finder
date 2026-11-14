// Turnstile verification on the server: it fails closed. / Verificación de Turnstile en el servidor: falla cerrado.
import { describe, expect, it, vi } from "vitest";
import { TURNSTILE_VERIFY_URL, verifyTurnstile } from "../src/lib/turnstile";

const reply = (ok: boolean, data: unknown) => vi.fn().mockResolvedValue({ ok, json: async () => data });

describe("verifyTurnstile", () => {
  it("accepts when Cloudflare says success", async () => {
    const fetchImpl = reply(true, { success: true });
    expect(await verifyTurnstile("tok", "secret", "190.1.2.3", fetchImpl)).toEqual({ ok: true });
    const [url, init] = fetchImpl.mock.calls[0] as [string, { method: string; body: URLSearchParams }];
    expect(url).toBe(TURNSTILE_VERIFY_URL);
    expect(init.method).toBe("POST");
    expect(init.body.get("secret")).toBe("secret");
    expect(init.body.get("response")).toBe("tok");
    expect(init.body.get("remoteip")).toBe("190.1.2.3");
  });

  it("does not send an address when there is none", async () => {
    const fetchImpl = reply(true, { success: true });
    await verifyTurnstile("tok", "secret", null, fetchImpl);
    expect((fetchImpl.mock.calls[0] as [string, { body: URLSearchParams }])[1].body.has("remoteip")).toBe(false);
  });

  it("refuses when Cloudflare says it is not valid", async () => {
    expect(await verifyTurnstile("tok", "secret", null, reply(true, { success: false, "error-codes": ["invalid-input-response"] }))).toEqual({ ok: false, reason: "invalid" });
  });

  it("fails closed when Cloudflare cannot be reached or answers an error", async () => {
    expect(await verifyTurnstile("tok", "secret", null, vi.fn().mockRejectedValue(new Error("network")))).toEqual({ ok: false, reason: "unavailable" });
    expect(await verifyTurnstile("tok", "secret", null, reply(false, {}))).toEqual({ ok: false, reason: "unavailable" });
    expect(await verifyTurnstile("tok", "secret", null, vi.fn().mockResolvedValue({ ok: true, json: async () => { throw new Error("bad json"); } }))).toEqual({ ok: false, reason: "unavailable" });
  });

  it("refuses an empty or oversized token without calling Cloudflare", async () => {
    const fetchImpl = reply(true, { success: true });
    expect(await verifyTurnstile("", "secret", null, fetchImpl)).toEqual({ ok: false, reason: "invalid" });
    expect(await verifyTurnstile("x".repeat(2049), "secret", null, fetchImpl)).toEqual({ ok: false, reason: "invalid" });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
