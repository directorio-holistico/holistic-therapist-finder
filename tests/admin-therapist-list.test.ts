import { describe, expect, it } from "vitest";
import {
  countryIdOf,
  groupByState,
  latestRevisionStatus,
  ratesStateOf,
  stateOf,
  toTherapistRow,
  whatsappOf,
  type ContactStub,
  type PersonStub,
  type ProfileStub,
} from "@/lib/admin/therapist-list-view";

const NOW = Date.parse("2026-11-25T12:00:00Z");
const PHONE = 1;
const profile = (extra: Partial<ProfileStub> = {}): ProfileStub => ({ id: "p1", person_id: "u1", display_name: "Ana Prueba", status_id: 2, location_id: 10, rates_confirmed_at: "2026-10-01T10:00:00Z", ...extra });
const person = (extra: Partial<PersonStub> = {}): PersonStub => ({ id: "u1", full_name: "Ana P. Persona", created_at: "2026-09-01T10:00:00Z", erased_at: null, ...extra });
const contact = (value: string, whatsapp: boolean, type = PHONE): ContactStub => ({ profile_id: "p1", contact_type_id: type, value, accepts_whatsapp: whatsapp });
const build = (extra: Partial<Parameters<typeof toTherapistRow>[0]> = {}) =>
  toTherapistRow({ profile: profile(), person: person(), profileCode: "published", revisionCode: "approved", countryIso: "AR", countryName: "Argentina", contacts: [], phoneTypeId: PHONE, months: 6, nowMs: NOW, ...extra });

describe("stateOf (one container per therapist)", () => {
  it("keeps a published profile as Publicado and only adds a note for a change on its way", () => {
    expect(stateOf("published", "approved")).toEqual({ state: "published", note: null });
    expect(stateOf("published", "pending_review")?.state).toBe("published");
    expect(stateOf("published", "pending_review")?.note).toMatch(/revisión/);
    expect(stateOf("published", "rejected")?.note).toMatch(/rechazado/);
    expect(stateOf("published", "draft")?.note).toMatch(/borrador/);
  });
  it("uses the latest revision for a profile that is not published yet", () => {
    expect(stateOf("unpublished", "pending_review")?.state).toBe("pending");
    expect(stateOf("unpublished", "rejected")?.state).toBe("rejected");
    expect(stateOf("unpublished", "draft")?.state).toBe("draft");
    expect(stateOf("unpublished", null)?.state).toBe("unpublished");
  });
  it("paused and suspended win over any revision, and erased or unknown are not listed", () => {
    expect(stateOf("paused", "pending_review")?.state).toBe("paused");
    expect(stateOf("suspended", "draft")?.state).toBe("suspended");
    expect(stateOf("erased", null)).toBeNull();
    expect(stateOf(null, null)).toBeNull();
  });
});

describe("latestRevisionStatus", () => {
  it("takes the newest revision of each profile and ignores discarded ones", () => {
    const rows = [
      { profile_id: "a", status_id: 1, created_at: "2026-11-01T10:00:00Z" },
      { profile_id: "a", status_id: 4, created_at: "2026-11-05T10:00:00Z" },
      { profile_id: "a", status_id: 5, created_at: "2026-11-09T10:00:00Z" }, // discarded, newer
      { profile_id: "b", status_id: 2, created_at: "2026-11-02T10:00:00Z" },
    ];
    const result = latestRevisionStatus(rows, 5);
    expect(result.get("a")).toBe(4);
    expect(result.get("b")).toBe(2);
  });
});

describe("ratesStateOf (same 'al día' rule as the database)", () => {
  it("is current inside the window, expired after it and none without a date", () => {
    expect(ratesStateOf("2026-06-01T10:00:00Z", 6, NOW)).toBe("current");
    expect(ratesStateOf("2026-05-01T10:00:00Z", 6, NOW)).toBe("expired");
    expect(ratesStateOf(null, 6, NOW)).toBe("none");
    expect(ratesStateOf("not a date", 6, NOW)).toBe("none");
  });
  it("follows the configured number of months", () => {
    expect(ratesStateOf("2026-05-01T10:00:00Z", 12, NOW)).toBe("current");
  });
});

describe("countryIdOf", () => {
  const parents = new Map<number, number | null>([[10, 5], [5, 1], [1, null], [20, null]]);
  it("walks from the city to the country", () => {
    expect(countryIdOf(10, parents)).toBe(1);
    expect(countryIdOf(20, parents)).toBe(20);
  });
  it("gives null with no location, a missing link or a loop", () => {
    expect(countryIdOf(null, parents)).toBeNull();
    expect(countryIdOf(99, parents)).toBeNull();
    expect(countryIdOf(1, new Map<number, number | null>([[1, 2], [2, 1]]))).toBeNull();
  });
});

describe("whatsappOf (the number is never exposed)", () => {
  it("builds a link only when the person marked WhatsApp and the number has the + code", () => {
    expect(whatsappOf([contact("+54 9 11 5555 1234", true)], PHONE)).toEqual({ link: "https://wa.me/5491155551234", hasPhone: true });
    expect(whatsappOf([contact("011 5555 1234", true)], PHONE).link).toBeNull();
    expect(whatsappOf([contact("+54 9 11 5555 1234", false)], PHONE)).toEqual({ link: null, hasPhone: true });
  });
  it("has no phone when there is none, and ignores other contact types", () => {
    expect(whatsappOf([], PHONE)).toEqual({ link: null, hasPhone: false });
    expect(whatsappOf([contact("+54 9 11 5555 1234", true, 2)], PHONE)).toEqual({ link: null, hasPhone: false });
    expect(whatsappOf([contact("+54 9 11 5555 1234", true)], null)).toEqual({ link: null, hasPhone: false });
  });
  it("never lets odd text become a link", () => {
    expect(whatsappOf([contact("+54<script>1155551234", true)], PHONE).link).toBeNull();
    expect(whatsappOf([contact("javascript:alert(1)", true)], PHONE).link).toBeNull();
  });
  it("uses the first valid WhatsApp phone when there are several", () => {
    const result = whatsappOf([contact("0111555", true), contact("+54 9 11 5555 1234", true)], PHONE);
    expect(result.link).toBe("https://wa.me/5491155551234");
  });
});

describe("toTherapistRow", () => {
  it("builds the row with the registration date, the prices date and no phone number", () => {
    const row = build({ contacts: [contact("+54 9 11 5555 1234", true)] });
    expect(row).not.toBeNull();
    expect(row?.name).toBe("Ana Prueba");
    expect(row?.registeredAt).toBe("2026-09-01T10:00:00Z");
    expect(row?.rates).toBe("current");
    expect(row?.state).toBe("published");
    expect(JSON.stringify(row)).not.toContain("5555 1234");
  });
  it("falls back to the person's name, then to 'Sin nombre'", () => {
    expect(build({ profile: profile({ display_name: null }) })?.name).toBe("Ana P. Persona");
    expect(build({ profile: profile({ display_name: " " }), person: person({ full_name: null }) })?.name).toBe("Sin nombre");
  });
  it("leaves out erased people, people that cannot be read and erased profiles", () => {
    expect(build({ person: person({ erased_at: "2026-11-01T10:00:00Z" }) })).toBeNull();
    expect(build({ person: undefined })).toBeNull();
    expect(build({ profileCode: "erased" })).toBeNull();
  });
  it("strips control characters from the name", () => {
    expect(build({ profile: profile({ display_name: "Ana‮\u0000 Prueba" }) })?.name).toBe("Ana Prueba");
  });
});

describe("groupByState", () => {
  it("returns the containers in the fixed order, sorted by name, without empty ones", () => {
    const rows = [
      build({ profile: profile({ id: "b", display_name: "Zoe" }) }),
      build({ profile: profile({ id: "a", display_name: "Álvaro" }) }),
      build({ profile: profile({ id: "c", display_name: "Carla" }), profileCode: "unpublished", revisionCode: "pending_review" }),
    ].filter((row) => row !== null);
    const groups = groupByState(rows);
    expect(groups.map((group) => group.state)).toEqual(["pending", "published"]);
    expect(groups[1]?.rows.map((row) => row.name)).toEqual(["Álvaro", "Zoe"]);
  });
});
