// Search pieces that need no network: reading the URL, building links, formatting, turning rows into cards.
// Piezas de la búsqueda que no necesitan red: leer la URL, armar enlaces, formatear, convertir filas en tarjetas.

import { describe, expect, it } from "vitest";
import { formatDate, formatMoney } from "../src/lib/format";
import { joinWithY, labelRateAudience, labelServiceMode } from "../src/lib/labels";
import { orderTherapies, parseRatesFrom, splitByGroup, toCard, type SearchCard } from "../src/lib/search";
import { MAX_PAGE, buildSearchHref, locationIdOf, parseSearchQuery } from "../src/lib/search-query";

describe("parseSearchQuery", () => {
  it("reads valid values", () => {
    expect(parseSearchQuery({ therapy: "5", country: "1", region: "7", mode: "remote", page: "3" })).toEqual({
      therapyId: 5, countryId: 1, regionId: 7, serviceMode: "remote", page: 3,
    });
  });

  it("ignores anything invalid instead of failing", () => {
    expect(parseSearchQuery({ therapy: "abc", country: "-4", region: "1.5", mode: "hack", page: "0" })).toEqual({
      therapyId: null, countryId: null, regionId: null, serviceMode: null, page: 1,
    });
    expect(parseSearchQuery({ page: String(MAX_PAGE + 1) }).page).toBe(1);
    expect(parseSearchQuery({ therapy: "99999999999" }).therapyId).toBeNull();
    expect(parseSearchQuery({})).toEqual({ therapyId: null, countryId: null, regionId: null, serviceMode: null, page: 1 });
  });

  it("takes the first value when a parameter is repeated", () => {
    expect(parseSearchQuery({ therapy: ["2", "9"] }).therapyId).toBe(2);
  });

  it("uses the region when there is one, else the country", () => {
    expect(locationIdOf(parseSearchQuery({ country: "1", region: "7" }))).toBe(7);
    expect(locationIdOf(parseSearchQuery({ country: "1" }))).toBe(1);
    expect(locationIdOf(parseSearchQuery({}))).toBeNull();
  });
});

describe("buildSearchHref", () => {
  it("builds a link with only what is set and omits page 1", () => {
    const query = parseSearchQuery({ therapy: "5", country: "1", mode: "remote" });
    expect(buildSearchHref(query, 1)).toBe("/buscar?therapy=5&country=1&mode=remote");
    expect(buildSearchHref(query, 2)).toBe("/buscar?therapy=5&country=1&mode=remote&page=2");
    expect(buildSearchHref(parseSearchQuery({}), 1)).toBe("/buscar");
  });
});

describe("formatting", () => {
  it("formats a timestamp in Argentina time, not UTC", () => {
    expect(formatDate("2026-11-12T23:30:00+00:00")).toBe("12/11/2026");
    expect(formatDate("2026-11-13T01:00:00+00:00")).toBe("12/11/2026");
    expect(formatDate("2026-11-13T03:00:00+00:00")).toBe("13/11/2026");
  });

  it("gives null for missing or invalid dates", () => {
    expect(formatDate(null)).toBeNull();
    expect(formatDate("nope")).toBeNull();
  });

  it("formats money with the currency code and falls back for an unknown code", () => {
    expect(formatMoney(20000, "ARS")).toMatch(/ARS.*20\.000|20\.000.*ARS/);
    expect(formatMoney(5, "zz")).toBe("5 zz");
  });

  it("shows a code as is when it has no label", () => {
    expect(labelServiceMode("remote")).toBe("A distancia");
    expect(labelServiceMode("hybrid")).toBe("hybrid");
    expect(labelRateAudience("own_country")).toMatch(/Residentes/);
  });
});

describe("rows to cards", () => {
  it("reads the lowest rates, own country first, and ignores odd values", () => {
    expect(parseRatesFrom({ other_countries: { amount: 30, currency: "USD" }, own_country: { amount: "15000.5", currency: "ARS" } })).toEqual([
      { audience: "own_country", amount: 15000.5, currency: "ARS" },
      { audience: "other_countries", amount: 30, currency: "USD" },
    ]);
    expect(parseRatesFrom(null)).toEqual([]);
    expect(parseRatesFrom({ own_country: { amount: "x", currency: "ARS" } })).toEqual([]);
  });

  it("builds a card, tolerating missing optional columns", () => {
    const card = toCard({
      result_group: 2, profile_id: "p1", display_name: "Ana", city_name: null, region_name: "Neuquén", country_name: "Argentina",
      therapy_names: ["Reiki"], rates_current: true, rates_confirmed_at: "2026-11-12T20:00:00+00:00", is_pinned: false,
    });
    expect(card).toMatchObject({ profileId: "p1", group: 2, place: "Neuquén, Argentina", therapies: ["Reiki"], ratesCurrent: true, isPinned: false, rates: [], languages: [] });
  });

  it("skips a row with no id or name", () => {
    expect(toCard({ display_name: "Sin id" })).toBeNull();
    expect(toCard({ profile_id: "x" })).toBeNull();
  });

  it("splits cards into consecutive groups", () => {
    const make = (id: string, group: number): SearchCard => toCard({ profile_id: id, display_name: id, result_group: group }) as SearchCard;
    const groups = splitByGroup([make("a", 1), make("b", 1), make("c", 3)]);
    expect(groups.map((g) => [g.group, g.cards.map((c) => c.profileId)])).toEqual([[1, ["a", "b"]], [3, ["c"]]]);
    expect(splitByGroup([])).toEqual([]);
  });
});

describe("orderTherapies", () => {
  const ids = [1, 2, 3];
  const names = ["Reiki", "Constelaciones familiares", "LNT® - La Nueva Terapia"];

  it("is alphabetical when no therapy was searched", () => {
    expect(orderTherapies(ids, names)).toEqual(["Constelaciones familiares", "LNT® - La Nueva Terapia", "Reiki"]);
  });

  it("puts the searched therapy first and keeps the rest alphabetical (A B C searching B -> B A C)", () => {
    expect(orderTherapies(ids, names, 1)).toEqual(["Reiki", "Constelaciones familiares", "LNT® - La Nueva Terapia"]);
    expect(orderTherapies(ids, names, 3)).toEqual(["LNT® - La Nueva Terapia", "Constelaciones familiares", "Reiki"]);
  });

  it("keeps the order when the searched therapy is already first or is not on the card", () => {
    expect(orderTherapies(ids, names, 2)).toEqual(["Constelaciones familiares", "LNT® - La Nueva Terapia", "Reiki"]);
    expect(orderTherapies(ids, names, 99)).toEqual(["Constelaciones familiares", "LNT® - La Nueva Terapia", "Reiki"]);
  });

  it("falls back to alphabetical when ids and names are not aligned or are missing", () => {
    expect(orderTherapies([1], names, 1)).toEqual(["Constelaciones familiares", "LNT® - La Nueva Terapia", "Reiki"]);
    expect(orderTherapies(null, null, 1)).toEqual([]);
  });

  it("toCard applies it", () => {
    const card = toCard({ profile_id: "p", display_name: "Ana", therapy_ids: ids, therapy_names: names }, 1);
    expect(card?.therapies[0]).toBe("Reiki");
  });
});

describe("joinWithY", () => {
  it("lowercases every label after the first", () => {
    expect(joinWithY(["Presencial", "A distancia"])).toBe("Presencial y a distancia");
    expect(joinWithY(["Individual", "Grupal"])).toBe("Individual y grupal");
    expect(joinWithY(["Presencial"])).toBe("Presencial");
    expect(joinWithY([])).toBe("");
  });
});
