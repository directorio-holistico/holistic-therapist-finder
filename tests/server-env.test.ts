// Secret environment: what is accepted and what is refused. / Entorno secreto: qué se acepta y qué se rechaza.
import { describe, expect, it } from "vitest";
import { isDummyTurnstileSecret, parseServerEnv } from "../src/lib/server-env";

const secretJwt = `h.${Buffer.from(JSON.stringify({ role: "service_role" })).toString("base64url")}.s`.padEnd(40, "x");
const anonJwt = `h.${Buffer.from(JSON.stringify({ role: "anon" })).toString("base64url")}.s`.padEnd(40, "x");
const base = { SUPABASE_SERVICE_ROLE_KEY: "sb_secret_" + "a".repeat(30), RATE_LIMIT_HMAC_KEY: "k".repeat(40), TURNSTILE_SECRET_KEY: "0x4AAAAAAA_real_secret_value" };

describe("parseServerEnv", () => {
  it("accepts good values (new and old style secret keys)", () => {
    expect(parseServerEnv(base, true).turnstileSecretKey).toBe("0x4AAAAAAA_real_secret_value");
    expect(parseServerEnv({ ...base, SUPABASE_SERVICE_ROLE_KEY: secretJwt }, true).serviceRoleKey).toBe(secretJwt);
  });

  it("refuses a public key where the secret goes, and names the variable but not the value", () => {
    expect(() => parseServerEnv({ ...base, SUPABASE_SERVICE_ROLE_KEY: anonJwt }, true)).toThrow(/SUPABASE_SERVICE_ROLE_KEY/);
    try {
      parseServerEnv({ ...base, SUPABASE_SERVICE_ROLE_KEY: anonJwt }, true);
    } catch (error) {
      expect(String(error)).not.toContain(anonJwt);
    }
  });

  it("refuses missing or short values", () => {
    expect(() => parseServerEnv({}, false)).toThrow(/Entorno de servidor inválido/);
    expect(() => parseServerEnv({ ...base, RATE_LIMIT_HMAC_KEY: "short" }, false)).toThrow(/RATE_LIMIT_HMAC_KEY/);
  });

  it("accepts a Turnstile dummy key off the real site and refuses it on the real site", () => {
    const dummy = { ...base, TURNSTILE_SECRET_KEY: "1x0000000000000000000000000000000AA" };
    expect(parseServerEnv(dummy, false).turnstileSecretKey).toBe("1x0000000000000000000000000000000AA");
    expect(() => parseServerEnv(dummy, true)).toThrow(/dummy/);
  });
});

describe("isDummyTurnstileSecret", () => {
  it("recognizes Cloudflare's three dummy secrets and nothing else", () => {
    expect(isDummyTurnstileSecret("1x0000000000000000000000000000000AA")).toBe(true);
    expect(isDummyTurnstileSecret("2x0000000000000000000000000000000AA")).toBe(true);
    expect(isDummyTurnstileSecret("3x0000000000000000000000000000000AA")).toBe(true);
    expect(isDummyTurnstileSecret("0x4AAAAAAA_real_secret_value")).toBe(false);
  });
});
