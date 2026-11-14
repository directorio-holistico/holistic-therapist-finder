import { describe, expect, it } from "vitest";
import { newPasswordSchema, passwordErrorMessage, passwordLoginSchema, PASSWORD_MAX_BYTES, PASSWORD_MIN_LENGTH } from "@/lib/auth/password";

const ok = (password: string, confirm = password) => newPasswordSchema.safeParse({ password, confirm });

describe("new password rules", () => {
  it("requires at least 10 characters", () => {
    expect(PASSWORD_MIN_LENGTH).toBe(10);
    expect(ok("123456789").success).toBe(false);
    expect(ok("1234567890").success).toBe(true);
  });
  it("counts characters, not bytes, for the minimum (accents and emoji are one each)", () => {
    expect(ok("ñandúñandú").success).toBe(true); // 10 characters, 14 bytes
    expect(ok("🙂".repeat(9)).success).toBe(false);
    expect(ok("🙂".repeat(10)).success).toBe(true); // 40 bytes
  });
  it("refuses more than 72 bytes (bcrypt would cut it silently)", () => {
    expect(PASSWORD_MAX_BYTES).toBe(72);
    expect(ok("a".repeat(72)).success).toBe(true);
    expect(ok("a".repeat(73)).success).toBe(false);
    expect(ok("ñ".repeat(37)).success).toBe(false); // 74 bytes
    expect(ok("ñ".repeat(36)).success).toBe(true); // 72 bytes
  });
  it("requires both fields to match and never trims", () => {
    expect(ok("abcdefghij", "abcdefghik").success).toBe(false);
    const spaces = ok("          "); // ten spaces are 10 characters: allowed, never trimmed
    expect(spaces.success).toBe(true);
    if (spaces.success) expect(spaces.data.password).toBe("          ");
    expect(ok(" abcdefghi ", "abcdefghi ").success).toBe(false);
  });
  it("gives a message for the field that failed", () => {
    const short = ok("abc");
    expect(!short.success && short.error.issues[0]?.path).toEqual(["password"]);
    const mismatch = ok("abcdefghij", "other");
    expect(!mismatch.success && mismatch.error.issues[0]?.path).toEqual(["confirm"]);
  });
});

describe("password error messages", () => {
  it("maps known codes and stays neutral for the rest", () => {
    expect(passwordErrorMessage("weak_password")).toMatch(/fácil de adivinar/);
    expect(passwordErrorMessage("same_password")).toMatch(/distinta/);
    expect(passwordErrorMessage("over_request_rate_limit")).toMatch(/muchos intentos/);
    expect(passwordErrorMessage(undefined)).toMatch(/Probá de nuevo/);
    expect(passwordErrorMessage("something_new")).toMatch(/Probá de nuevo/);
  });
});

describe("password login input", () => {
  it("cleans the mail, keeps the password untouched", () => {
    const parsed = passwordLoginSchema.safeParse({ email: "  Ana@Example.COM ", password: " p ass " });
    expect(parsed.success && parsed.data).toEqual({ email: "ana@example.com", password: " p ass " });
  });
  it("refuses an empty password, a bad mail and an absurd length", () => {
    expect(passwordLoginSchema.safeParse({ email: "a@b.co", password: "" }).success).toBe(false);
    expect(passwordLoginSchema.safeParse({ email: "nope", password: "x" }).success).toBe(false);
    expect(passwordLoginSchema.safeParse({ email: "a@b.co", password: "x".repeat(201) }).success).toBe(false);
  });
});
