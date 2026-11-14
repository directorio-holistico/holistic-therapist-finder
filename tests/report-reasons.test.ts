// The reasons in the form must be the ones in the database catalog. / Los motivos del formulario deben ser los del catálogo de la base.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { REPORT_REASONS, REPORT_REASON_CODES } from "../src/lib/report-reasons";

const MIGRATION = "supabase/migrations/20261111200000_reports_and_suspension.sql";

describe("report reasons", () => {
  it("match the codes the migration inserts, in the same order", () => {
    const sql = readFileSync(MIGRATION, "utf8");
    const block = /insert into public\.report_reasons \(code, sort_order\) values([^;]+);/.exec(sql);
    expect(block).not.toBeNull();
    const codes = [...(block?.[1] ?? "").matchAll(/\('([a-z_]+)',\s*\d+\)/g)].map((match) => match[1]);
    expect(codes.length).toBeGreaterThan(0);
    expect([...REPORT_REASON_CODES]).toEqual(codes);
  });

  it("have a label for each code and no repeated code", () => {
    expect(new Set(REPORT_REASON_CODES).size).toBe(REPORT_REASONS.length);
    for (const reason of REPORT_REASONS) expect(reason.label.trim().length).toBeGreaterThan(3);
  });
});
