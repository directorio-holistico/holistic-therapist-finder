import { describe, expect, it } from "vitest";
import { chunksOf, daysSince, displayNameOf, elapsedLabel, phoneOf, pickFollowUps, toFollowUpItem, type RevisionStub } from "@/lib/admin/followup-view";

const IDS = { rejected: 3, draft: 1 };
const TYPES = new Map([[1, "phone"], [2, "email"]]);
const stub = (id: string, profile: string, status: number, created: string, extra: Partial<RevisionStub> = {}): RevisionStub =>
  ({ id, profile_id: profile, status_id: status, created_at: created, decided_at: null, rejection_reason: null, ...extra });

describe("pickFollowUps (only the latest revision of each profile counts)", () => {
  it("lists a profile whose latest revision is rejected, oldest rejection first", () => {
    const rows = [
      stub("r2", "b", 3, "2026-11-10T10:00:00Z", { decided_at: "2026-11-12T10:00:00Z", rejection_reason: "x" }),
      stub("r1", "a", 3, "2026-11-01T10:00:00Z", { decided_at: "2026-11-05T10:00:00Z", rejection_reason: "y" }),
    ];
    expect(pickFollowUps(rows, IDS).rejected.map((r) => r.id)).toEqual(["r1", "r2"]);
  });
  it("ignores a rejection when a newer revision exists (the therapist already reacted)", () => {
    const rows = [
      stub("old", "a", 3, "2026-11-01T10:00:00Z", { decided_at: "2026-11-02T10:00:00Z", rejection_reason: "x" }),
      stub("new", "a", 1, "2026-11-03T10:00:00Z"),
    ];
    const result = pickFollowUps(rows, IDS);
    expect(result.rejected).toEqual([]);
    expect(result.drafts.map((r) => r.id)).toEqual(["new"]);
  });
  it("does not depend on the order of the rows", () => {
    const rows = [
      stub("new", "a", 1, "2026-11-03T10:00:00Z"),
      stub("old", "a", 3, "2026-11-01T10:00:00Z", { decided_at: "2026-11-02T10:00:00Z", rejection_reason: "x" }),
    ];
    expect(pickFollowUps([...rows].reverse(), IDS)).toEqual(pickFollowUps(rows, IDS));
  });
  it("ignores pending and approved revisions", () => {
    const rows = [stub("p", "a", 2, "2026-11-03T10:00:00Z"), stub("ok", "b", 4, "2026-11-03T10:00:00Z")];
    expect(pickFollowUps(rows, IDS)).toEqual({ rejected: [], drafts: [] });
  });
  it("sorts drafts from the oldest", () => {
    const rows = [stub("d2", "b", 1, "2026-11-09T10:00:00Z"), stub("d1", "a", 1, "2026-11-02T10:00:00Z")];
    expect(pickFollowUps(rows, IDS).drafts.map((r) => r.id)).toEqual(["d1", "d2"]);
  });
});

describe("elapsed time", () => {
  const now = Date.parse("2026-11-22T16:00:00Z");
  it("counts whole days and never goes negative", () => {
    expect(daysSince("2026-11-12T16:00:00Z", now)).toBe(10);
    expect(daysSince("2026-11-22T10:00:00Z", now)).toBe(0);
    expect(daysSince("2026-11-23T10:00:00Z", now)).toBe(0);
  });
  it("returns null when the date cannot be read", () => {
    expect(daysSince(null, now)).toBeNull();
    expect(daysSince("no es fecha", now)).toBeNull();
  });
  it("writes the label in Spanish", () => {
    expect(elapsedLabel(0)).toBe("hoy");
    expect(elapsedLabel(1)).toBe("hace 1 día");
    expect(elapsedLabel(12)).toBe("hace 12 días");
    expect(elapsedLabel(null)).toBe("fecha desconocida");
  });
});

describe("phoneOf (text always; a WhatsApp link only with the country code)", () => {
  it("gives a link when WhatsApp is marked and the number starts with +", () => {
    const phone = phoneOf({ contacts: [{ contact_type_id: 1, value: "+54 299 555 0101", accepts_whatsapp: true }] }, TYPES);
    expect(phone).toEqual({ text: "+54 299 555 0101", whatsapp: true, whatsappLink: "https://wa.me/542995550101" });
  });
  it("gives no link without the + or without the WhatsApp mark", () => {
    expect(phoneOf({ contacts: [{ contact_type_id: 1, value: "299 555 0101", accepts_whatsapp: true }] }, TYPES)?.whatsappLink).toBeNull();
    expect(phoneOf({ contacts: [{ contact_type_id: 1, value: "+54 299 555 0101", accepts_whatsapp: false }] }, TYPES)?.whatsappLink).toBeNull();
  });
  it("gives no link for anything that is not a plain phone number", () => {
    expect(phoneOf({ contacts: [{ contact_type_id: 1, value: "+54 <script>", accepts_whatsapp: true }] }, TYPES)?.whatsappLink).toBeNull();
  });
  it("returns null without a phone or for a payload of the wrong shape", () => {
    expect(phoneOf({ contacts: [{ contact_type_id: 2, value: "a@b.c" }] }, TYPES)).toBeNull();
    expect(phoneOf("basura", TYPES)).toBeNull();
    expect(phoneOf(null, TYPES)).toBeNull();
  });
});

describe("toFollowUpItem", () => {
  const now = Date.parse("2026-11-22T16:00:00Z");
  const base = { payload: { display_name: "Ana" }, profileDisplayName: "Ana P", personName: "Ana Pérez", email: "ana@example.com", profileStatusCode: "unpublished", contactTypeCodes: TYPES, nowMs: now };

  it("uses the rejection date and keeps the reason for a rejected revision", () => {
    const item = toFollowUpItem({ ...base, kind: "rejected", stub: stub("r", "p", 3, "2026-11-01T10:00:00Z", { decided_at: "2026-11-12T16:00:00Z", rejection_reason: "Promete curas" }) });
    expect(item).toMatchObject({ name: "Ana", date: "2026-11-12T16:00:00Z", days: 10, reason: "Promete curas", profileStatus: "unpublished", email: "ana@example.com" });
  });
  it("uses the creation date and no reason for a draft", () => {
    const item = toFollowUpItem({ ...base, kind: "draft", stub: stub("d", "p", 1, "2026-11-20T16:00:00Z", { rejection_reason: "no debería verse" }) });
    expect(item).toMatchObject({ date: "2026-11-20T16:00:00Z", days: 2, reason: null });
  });
  it("falls back from the draft name to the profile name, then to the person, then to a fixed text", () => {
    const stubRow = stub("d", "p", 1, "2026-11-20T16:00:00Z");
    expect(toFollowUpItem({ ...base, kind: "draft", stub: stubRow, payload: {} }).name).toBe("Ana P");
    expect(toFollowUpItem({ ...base, kind: "draft", stub: stubRow, payload: {}, profileDisplayName: null }).name).toBe("Ana Pérez");
    expect(toFollowUpItem({ ...base, kind: "draft", stub: stubRow, payload: {}, profileDisplayName: " ", personName: null }).name).toBe("Sin nombre");
  });
  it("removes control and invisible characters from the texts and drops an empty e-mail", () => {
    const stubRow = stub("d", "p", 1, "2026-11-20T16:00:00Z");
    expect(toFollowUpItem({ ...base, kind: "draft", stub: stubRow, payload: { display_name: "A\u0000n​a" } }).name).toBe("Ana");
    expect(toFollowUpItem({ ...base, kind: "draft", stub: stubRow, email: "  " }).email).toBeNull();
  });
});

describe("displayNameOf and chunksOf", () => {
  it("reads a text name only", () => {
    expect(displayNameOf({ display_name: "Ana" })).toBe("Ana");
    expect(displayNameOf({ display_name: 5 })).toBeNull();
    expect(displayNameOf({ display_name: "  " })).toBeNull();
    expect(displayNameOf("x")).toBeNull();
  });
  it("splits a list into groups of a given size", () => {
    expect(chunksOf([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunksOf([], 3)).toEqual([]);
  });
});
