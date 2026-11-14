// The "origin" of a visitor for the daily limit (ADR-0003): the address is normalized (IPv4 whole; IPv6 cut to its /64 prefix,
// because one home or one phone gets a whole /64) and turned into a keyed hash (HMAC-SHA256). The database only ever sees the
// 64 hex characters; the address itself is never stored or logged.
// El "origen" de un visitante para el límite diario (ADR-0003): la dirección se normaliza (IPv4 entera; IPv6 recortada a su prefijo
// /64, porque una casa o un celular recibe un /64 entero) y se convierte en un hash con clave (HMAC-SHA256). La base solo ve los
// 64 caracteres hexadecimales; la dirección nunca se guarda ni se escribe en logs.

import { createHmac } from "node:crypto";
import { isIPv4, isIPv6 } from "node:net";

// Expands an IPv6 text (already known to be valid) to its 8 groups of 16 bits.
function expandIPv6(value: string): number[] | null {
  let text = value.toLowerCase();
  const lastColon = text.lastIndexOf(":");
  const tail = text.slice(lastColon + 1);
  if (tail.includes(".")) {
    if (!isIPv4(tail)) return null;
    const [a = 0, b = 0, c = 0, d = 0] = tail.split(".").map(Number);
    text = `${text.slice(0, lastColon + 1)}${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const split = (part: string | undefined) => (part === undefined || part === "" ? [] : part.split(":"));
  const head = split(halves[0]);
  const rest = halves.length === 2 ? split(halves[1]) : [];
  const gap = 8 - head.length - rest.length;
  if (halves.length === 2 ? gap < 1 : gap !== 0) return null;
  const groups = [...head, ...Array<string>(halves.length === 2 ? gap : 0).fill("0"), ...rest].map((group) => parseInt(group, 16));
  return groups.length === 8 && groups.every((group) => Number.isInteger(group) && group >= 0 && group <= 0xffff) ? groups : null;
}

// null = not a usable address.
export function normalizeAddress(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const first = (raw.split(",")[0] ?? "").trim().replace(/%.*$/, "");
  if (first.length === 0 || first.length > 64) return null;
  if (isIPv4(first)) return first.split(".").map(Number).join(".");
  if (!isIPv6(first)) return null;
  const groups = expandIPv6(first);
  if (!groups) return null;
  const [g0, g1, g2, g3, g4, g5, g6 = 0, g7 = 0] = groups;
  // IPv4 written inside IPv6 (::ffff:a.b.c.d) counts as that IPv4.
  if (g0 === 0 && g1 === 0 && g2 === 0 && g3 === 0 && g4 === 0 && g5 === 0xffff) {
    return `${g6 >> 8}.${g6 & 255}.${g7 >> 8}.${g7 & 255}`;
  }
  return `${[g0, g1, g2, g3].map((group) => (group ?? 0).toString(16)).join(":")}::/64`;
}

// Vercel puts the real address of the client in x-forwarded-for (it overwrites what the client sent). / Vercel pone la dirección real
// del cliente en x-forwarded-for (sobrescribe lo que mandó el cliente).
export function clientAddress(headers: Headers): string | null {
  return normalizeAddress(headers.get("x-forwarded-for") ?? headers.get("x-real-ip"));
}

export function originHash(address: string, key: string): string {
  return createHmac("sha256", key).update(`reveal|${address}`).digest("hex");
}
