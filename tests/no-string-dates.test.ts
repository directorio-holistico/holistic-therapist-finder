// Guard test: dates must never be built from a bare "YYYY-MM-DD" string.
// Prueba guardiana: las fechas nunca se arman desde un texto "AAAA-MM-DD" suelto.
//
// `new Date("2026-11-11")` is parsed as UTC midnight, but `new Date("2026-11-11T00:00")`
// is parsed as local time. Mixing both shifts dates by one day depending on the timezone.
// Rule: store `timestamptz` (UTC) and build dates from full ISO strings with "Z" or a number.
// `new Date("2026-11-11")` se interpreta como medianoche UTC, pero `new Date("2026-11-11T00:00")`
// como hora local. Mezclarlos corre las fechas un día según la zona horaria.
// Regla: guardar `timestamptz` (UTC) y armar fechas desde ISO completo con "Z" o desde un número.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// Matches new Date("2026-11-11") / new Date('2026-11-11') / new Date(`2026-11-11`)
const BARE_DATE = /new\s+Date\(\s*["'`]\d{4}-\d{2}-\d{2}["'`]\s*\)/;

function sourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      files.push(...sourceFiles(path));
    } else if (/\.(ts|tsx)$/.test(name)) {
      files.push(path);
    }
  }
  return files;
}

describe("date handling", () => {
  it("the guard pattern detects bare date strings", () => {
    expect(BARE_DATE.test('new Date("2026-11-11")')).toBe(true);
    expect(BARE_DATE.test("new Date('2026-11-11')")).toBe(true);
    expect(BARE_DATE.test("new Date(`2026-11-11`)")).toBe(true);
  });

  it("the guard pattern accepts full UTC timestamps and numbers", () => {
    expect(BARE_DATE.test('new Date("2026-11-11T00:00:00Z")')).toBe(false);
    expect(BARE_DATE.test("new Date(Date.UTC(2026, 10, 11))")).toBe(false);
    expect(BARE_DATE.test("new Date(1794369329837)")).toBe(false);
  });

  it("no source file under src/ builds a Date from a bare YYYY-MM-DD string", () => {
    const offenders = sourceFiles("src").filter((file) =>
      BARE_DATE.test(readFileSync(file, "utf8")),
    );
    expect(offenders).toEqual([]);
  });
});
