import { describe, expect, it } from "vitest";
import { DEFAULT_AFTER_LOGIN, confirmSchema, loginSchema, safeNextPath } from "../src/lib/auth/params";

describe("safeNextPath", () => {
  it("keeps a path inside the site", () => {
    expect(safeNextPath("/mi-perfil")).toBe("/mi-perfil");
    expect(safeNextPath("/mi-perfil/editar?x=1")).toBe("/mi-perfil/editar?x=1");
  });

  it("refuses anything that could leave the site (open redirect)", () => {
    for (const bad of ["https://evil.test", "//evil.test", "/\\evil.test", "evil.test", "javascript:alert(1)", "/a\nb", "", undefined, null, 5]) {
      expect(safeNextPath(bad)).toBe(DEFAULT_AFTER_LOGIN);
    }
    expect(safeNextPath("/" + "a".repeat(300))).toBe(DEFAULT_AFTER_LOGIN);
  });

  it("uses the fallback it is given", () => {
    expect(safeNextPath("//x", "/")).toBe("/");
  });
});

describe("loginSchema", () => {
  it("trims and lowercases a valid email", () => {
    expect(loginSchema.parse({ email: "  Ana@Example.COM " }).email).toBe("ana@example.com");
  });

  it("refuses wrong or missing emails", () => {
    for (const email of ["", "ana", "ana@", "@x.com", "a b@x.com", "a".repeat(260) + "@x.com", null, undefined]) {
      expect(loginSchema.safeParse({ email }).success).toBe(false);
    }
  });
});

describe("confirmSchema", () => {
  it("accepts the three link types", () => {
    for (const type of ["email", "magiclink", "signup"]) {
      expect(confirmSchema.safeParse({ token_hash: "abcdef1234567890", type }).success).toBe(true);
    }
  });

  it("refuses other types, short or spaced tokens and missing values", () => {
    expect(confirmSchema.safeParse({ token_hash: "abcdef1234567890", type: "recovery" }).success).toBe(false);
    expect(confirmSchema.safeParse({ token_hash: "short", type: "email" }).success).toBe(false);
    expect(confirmSchema.safeParse({ token_hash: "has space 1234567", type: "email" }).success).toBe(false);
    expect(confirmSchema.safeParse({ type: "email" }).success).toBe(false);
  });
});
