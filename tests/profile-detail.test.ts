// Public profile data: turning the database row into the page data, safe links, odd JSON, and the read.
// Datos del perfil público: convertir la fila de la base en datos de página, enlaces seguros, JSON raro y la lectura.

import { describe, expect, it, vi } from "vitest";
import { buildLinks, loadPublicProfile, parseTherapies, safeHttpUrl, toProfileDetail, type DetailRow } from "../src/lib/profile-detail";

const ID = "20000000-0000-0000-0000-0000000029a1";

const row: DetailRow = {
  profile_id: ID,
  display_name: "Lucía Ferrante",
  headline: "Sesiones de LNT y Reiki",
  city_name: "Cinco Saltos",
  region_name: "Río Negro",
  country_name: "Argentina",
  country_iso: "AR",
  languages: ["es"],
  is_pinned: false,
  practice_start_year: 2015,
  rates_current: true,
  rates_confirmed_at: "2026-11-02T12:00:00Z",
  instagram: "lucia.reiki",
  website: "https://www.lucia.example/",
  therapies_detail: [
    {
      therapy_id: 24, name: "LNT® - La Nueva Terapia", session_minutes: 60,
      service_modes: ["in_person"], session_formats: ["individual"],
      rates: [{ audience: "other_countries", amount: 40, currency: "USD" }, { audience: "own_country", amount: 20000, currency: "ARS" }],
    },
    { therapy_id: 1, name: "Reiki", session_minutes: null, service_modes: ["remote"], session_formats: ["individual"], rates: [] },
  ],
};

describe("toProfileDetail", () => {
  it("builds the page data with therapies sorted by name and rates with own country first", () => {
    const detail = toProfileDetail(row);
    expect(detail?.displayName).toBe("Lucía Ferrante");
    expect(detail?.place).toBe("Cinco Saltos, Río Negro, Argentina");
    expect(detail?.therapies.map((t) => t.name)).toEqual(["LNT® - La Nueva Terapia", "Reiki"]);
    expect(detail?.therapies[0]?.serviceModes).toEqual(["in_person"]);
    expect(detail?.therapies[1]?.serviceModes).toEqual(["remote"]);
    expect(detail?.therapies[0]?.rates.map((r) => r.audience)).toEqual(["own_country", "other_countries"]);
    expect(detail?.therapies[1]?.sessionMinutes).toBeNull();
  });

  it("returns null without id or name", () => {
    expect(toProfileDetail({ display_name: "x" })).toBeNull();
    expect(toProfileDetail({ profile_id: ID })).toBeNull();
  });
});

describe("parseTherapies", () => {
  it("gives an empty list for anything odd", () => {
    expect(parseTherapies(null)).toEqual([]);
    expect(parseTherapies("x")).toEqual([]);
    expect(parseTherapies([{ therapy_id: "1" }])).toEqual([]);
  });

  it("drops a broken rate but keeps the therapy", () => {
    const parsed = parseTherapies([{ therapy_id: 1, name: "Reiki", service_modes: [], session_formats: [], rates: [{ audience: "own_country", amount: "x", currency: "ARS" }] }]);
    expect(parsed[0]?.rates).toEqual([]);
  });
});

describe("links", () => {
  it("accepts only http(s)", () => {
    expect(safeHttpUrl("javascript:alert(1)")).toBeNull();
    expect(safeHttpUrl("ftp://x.example")).toBeNull();
    expect(safeHttpUrl("no es una url")).toBeNull();
    expect(safeHttpUrl("https://ok.example/")?.hostname).toBe("ok.example");
  });

  it("rebuilds Instagram from the user name and shows the site name", () => {
    const links = buildLinks({ instagram: "lucia.reiki", website: "https://www.lucia.example/" });
    expect(links).toEqual([
      { kind: "website", href: "https://www.lucia.example/", text: "lucia.example" },
      { kind: "instagram", href: "https://www.instagram.com/lucia.reiki", text: "@lucia.reiki" },
    ]);
  });

  it("drops an invalid Instagram user and social links from another site or without https", () => {
    expect(buildLinks({ instagram: "no valido!" })).toEqual([]);
    expect(buildLinks({ facebook: "https://evil.example/facebook.com", tiktok: "http://www.tiktok.com/@a_b", youtube: "https://notyoutube.com/@x" })).toEqual([]);
  });

  it("keeps a valid social link", () => {
    expect(buildLinks({ tiktok: "https://www.tiktok.com/@lucia.reiki" })).toEqual([
      { kind: "tiktok", href: "https://www.tiktok.com/@lucia.reiki", text: "tiktok.com/@lucia.reiki" },
    ]);
  });
});

describe("loadPublicProfile", () => {
  function clientReturning(result: { data: unknown; error: { message: string } | null }) {
    const limit = vi.fn().mockResolvedValue(result);
    const eq = vi.fn().mockReturnValue({ limit });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    return { client: { from } as never, from, eq };
  }

  it("does not touch the database for an id that is not a UUID", async () => {
    const { client, from } = clientReturning({ data: [], error: null });
    expect(await loadPublicProfile(client, "1 or 1=1")).toBeNull();
    expect(from).not.toHaveBeenCalled();
  });

  it("reads the public view by profile id", async () => {
    const { client, from, eq } = clientReturning({ data: [row], error: null });
    const detail = await loadPublicProfile(client, ID);
    expect(from).toHaveBeenCalledWith("public_profile_detail");
    expect(eq).toHaveBeenCalledWith("profile_id", ID);
    expect(detail?.displayName).toBe("Lucía Ferrante");
  });

  it("returns null when the profile is not there (or not public)", async () => {
    const { client } = clientReturning({ data: [], error: null });
    expect(await loadPublicProfile(client, ID)).toBeNull();
  });

  it("throws on a database error", async () => {
    const { client } = clientReturning({ data: null, error: { message: "boom" } });
    await expect(loadPublicProfile(client, ID)).rejects.toThrow("boom");
  });
});
