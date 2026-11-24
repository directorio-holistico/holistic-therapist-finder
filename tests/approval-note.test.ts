import { describe, expect, it } from "vitest";
import { APPROVAL_NOTE_MAX, readApprovalNote } from "@/lib/admin/approval-note";

describe("readApprovalNote", () => {
  it("treats a missing or blank message as no message", () => {
    expect(readApprovalNote(null)).toEqual({ ok: true, value: null });
    expect(readApprovalNote("")).toEqual({ ok: true, value: null });
    expect(readApprovalNote("  \n  ")).toEqual({ ok: true, value: null });
  });
  it("trims the message and keeps its line breaks", () => {
    expect(readApprovalNote("  Hola\n\n1) Foto  ")).toEqual({ ok: true, value: "Hola\n\n1) Foto" });
  });
  it("accepts exactly the limit and refuses one more", () => {
    expect(readApprovalNote("a".repeat(APPROVAL_NOTE_MAX))).toEqual({ ok: true, value: "a".repeat(APPROVAL_NOTE_MAX) });
    const over = readApprovalNote("a".repeat(APPROVAL_NOTE_MAX + 1));
    expect(over.ok).toBe(false);
  });
  it("counts characters, not UTF-16 units", () => {
    expect(readApprovalNote("😀".repeat(APPROVAL_NOTE_MAX)).ok).toBe(true);
    expect(readApprovalNote("😀".repeat(APPROVAL_NOTE_MAX + 1)).ok).toBe(false);
  });
  it("refuses a file or any non-text value", () => {
    expect(readApprovalNote(new File(["x"], "x.txt")).ok).toBe(false);
  });
});
