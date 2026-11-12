// Environment validation: what is accepted, what is refused, and that a refusal never echoes a secret.
// Validación del entorno: qué se acepta, qué se rechaza, y que un rechazo nunca repite un secreto.

import { describe, expect, it } from "vitest";
import { parsePublicEnv } from "../src/lib/env";

const URL_OK = "https://abcdefghijklmnopqrst.supabase.co";
const KEY_OK = "sb_publishable_0123456789abcdefghij";

function fakeJwt(role: string): string {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ role })}.signature-not-checked`;
}

describe("parsePublicEnv", () => {
  it("accepts a https address and a public key, and trims spaces", () => {
    const env = parsePublicEnv({
      NEXT_PUBLIC_SUPABASE_URL: ` ${URL_OK} `,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: ` ${KEY_OK} `,
    });
    expect(env).toEqual({ supabaseUrl: URL_OK, supabaseAnonKey: KEY_OK });
  });

  it("accepts an old-style anon JWT", () => {
    const key = fakeJwt("anon");
    const env = parsePublicEnv({ NEXT_PUBLIC_SUPABASE_URL: URL_OK, NEXT_PUBLIC_SUPABASE_ANON_KEY: key });
    expect(env.supabaseAnonKey).toBe(key);
  });

  it("accepts plain http only for localhost", () => {
    const base = { NEXT_PUBLIC_SUPABASE_ANON_KEY: KEY_OK };
    expect(() => parsePublicEnv({ ...base, NEXT_PUBLIC_SUPABASE_URL: "http://localhost:54321" })).not.toThrow();
    expect(() => parsePublicEnv({ ...base, NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321" })).not.toThrow();
    expect(() => parsePublicEnv({ ...base, NEXT_PUBLIC_SUPABASE_URL: "http://example.com" })).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
  });

  it("refuses missing, empty or malformed values and names the variable", () => {
    expect(() => parsePublicEnv({})).toThrow(/NEXT_PUBLIC_SUPABASE_URL[\s\S]*NEXT_PUBLIC_SUPABASE_ANON_KEY/);
    expect(() => parsePublicEnv({ NEXT_PUBLIC_SUPABASE_URL: "", NEXT_PUBLIC_SUPABASE_ANON_KEY: KEY_OK })).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
    expect(() => parsePublicEnv({ NEXT_PUBLIC_SUPABASE_URL: "not a url", NEXT_PUBLIC_SUPABASE_ANON_KEY: KEY_OK })).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
    expect(() => parsePublicEnv({ NEXT_PUBLIC_SUPABASE_URL: URL_OK, NEXT_PUBLIC_SUPABASE_ANON_KEY: "short" })).toThrow(/NEXT_PUBLIC_SUPABASE_ANON_KEY/);
  });

  it("refuses a secret key where the public key goes, in both formats", () => {
    const base = { NEXT_PUBLIC_SUPABASE_URL: URL_OK };
    expect(() => parsePublicEnv({ ...base, NEXT_PUBLIC_SUPABASE_ANON_KEY: "sb_secret_0123456789abcdefghij" })).toThrow(/SECRET/);
    expect(() => parsePublicEnv({ ...base, NEXT_PUBLIC_SUPABASE_ANON_KEY: fakeJwt("service_role") })).toThrow(/SECRET/);
  });

  it("never repeats a rejected value in the error message", () => {
    const secret = "sb_secret_this-value-must-not-be-printed";
    let message = "";
    try {
      parsePublicEnv({ NEXT_PUBLIC_SUPABASE_URL: "http://example.com/leaky-path", NEXT_PUBLIC_SUPABASE_ANON_KEY: secret });
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }
    expect(message).not.toBe("");
    expect(message).not.toContain(secret);
    expect(message).not.toContain("leaky-path");
  });
});
