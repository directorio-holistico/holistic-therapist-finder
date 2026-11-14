// The origin of a visitor for the daily limit: normalization and keyed hash. / El origen del visitante para el límite diario.
import { describe, expect, it } from "vitest";
import { clientAddress, normalizeAddress, originHash } from "../src/lib/origin";

describe("normalizeAddress", () => {
  it("keeps an IPv4 and cleans it", () => {
    expect(normalizeAddress("190.12.34.56")).toBe("190.12.34.56");
    expect(normalizeAddress(" 190.12.34.56 ")).toBe("190.12.34.56");
  });

  it("takes the first address of a list", () => {
    expect(normalizeAddress("190.12.34.56, 10.0.0.1")).toBe("190.12.34.56");
  });

  it("cuts IPv6 to its /64 prefix, whatever way it is written", () => {
    const a = normalizeAddress("2001:db8:abcd:12:1111:2222:3333:4444");
    const b = normalizeAddress("2001:0db8:ABCD:0012:ffff:0:0:1");
    expect(a).toBe("2001:db8:abcd:12::/64");
    expect(b).toBe(a);
    expect(normalizeAddress("2001:db8::1")).toBe("2001:db8:0:0::/64");
    expect(normalizeAddress("::1")).toBe("0:0:0:0::/64");
  });

  it("treats an IPv4 written inside IPv6 as that IPv4", () => {
    expect(normalizeAddress("::ffff:190.12.34.56")).toBe("190.12.34.56");
  });

  it("drops a zone id", () => {
    expect(normalizeAddress("fe80::1%eth0")).toBe("fe80:0:0:0::/64");
  });

  it("refuses what is not an address", () => {
    for (const value of [null, undefined, "", "   ", "no-es-ip", "999.1.1.1", "1.2.3", "a".repeat(100), "2001:db8::zz"]) {
      expect(normalizeAddress(value)).toBeNull();
    }
  });
});

describe("clientAddress", () => {
  it("reads x-forwarded-for first, then x-real-ip", () => {
    expect(clientAddress(new Headers({ "x-forwarded-for": "190.1.2.3", "x-real-ip": "10.0.0.1" }))).toBe("190.1.2.3");
    expect(clientAddress(new Headers({ "x-real-ip": "10.0.0.1" }))).toBe("10.0.0.1");
    expect(clientAddress(new Headers())).toBeNull();
  });
});

describe("originHash", () => {
  const key = "k".repeat(40);

  it("is 64 lower-case hex characters (what the database accepts)", () => {
    expect(originHash("190.1.2.3", key)).toMatch(/^[0-9a-f]{64}$/);
  });

  it("is stable for the same address and key, and differs with another address or another key", () => {
    expect(originHash("190.1.2.3", key)).toBe(originHash("190.1.2.3", key));
    expect(originHash("190.1.2.3", key)).not.toBe(originHash("190.1.2.4", key));
    expect(originHash("190.1.2.3", key)).not.toBe(originHash("190.1.2.3", "j".repeat(40)));
  });

  it("does not contain the address", () => {
    expect(originHash("190.1.2.3", key)).not.toContain("190");
  });
});
