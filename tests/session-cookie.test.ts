import { describe, expect, it } from "vitest";
import { hasSessionCookie } from "../src/lib/auth/session-cookie";

describe("hasSessionCookie", () => {
  it("sees the session cookie, whole or in pieces / ve la cookie de sesión, entera o en trozos", () => {
    expect(hasSessionCookie(["theme", "sb-abcdefgh-auth-token"])).toBe(true);
    expect(hasSessionCookie(["sb-abcdefgh-auth-token.0", "sb-abcdefgh-auth-token.1"])).toBe(true);
  });
  it("does not take other cookies for a session / no toma otras cookies por una sesión", () => {
    expect(hasSessionCookie([])).toBe(false);
    expect(hasSessionCookie(["theme", "sb-abcdefgh-auth-token-code-verifier", "my-auth-token", "sb-x-auth-token-evil"])).toBe(false);
  });
});
