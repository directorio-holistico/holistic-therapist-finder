// Catalog reading: pure merge/sort, and the shape of the queries (checked with a fake client; no network).
// Lectura de catálogos: unión/orden puros, y la forma de las consultas (con un cliente falso; sin red).

import { describe, expect, it } from "vitest";
import { THERAPIES_LISTED_FIRST, buildOptions, listLocations, listTherapies } from "../src/lib/catalogs";

type Call = { table: string; steps: Array<[string, ...unknown[]]> };

// Fake query builder: records the chain and answers from a table map. Awaiting it returns { data, error }.
// Constructor de consultas falso: registra la cadena y responde desde un mapa de tablas.
function fakeClient(tables: Record<string, unknown[] | { error: string }>) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, steps: [] };
      calls.push(call);
      const builder: Record<string, unknown> = {};
      for (const method of ["select", "eq", "is", "in", "limit"]) {
        builder[method] = (...args: unknown[]) => {
          call.steps.push([method, ...args]);
          return builder;
        };
      }
      builder.then = (resolve: (value: unknown) => unknown) => {
        const answer = tables[table];
        const result = Array.isArray(answer)
          ? { data: answer, error: null }
          : { data: null, error: { message: answer?.error ?? "no table" } };
        return Promise.resolve(result).then(resolve);
      };
      return builder;
    },
  };
  return { client: client as never, calls };
}

describe("buildOptions", () => {
  it("uses the translated name, then the code, then the id", () => {
    const options = buildOptions(
      [{ id: 1, code: "reiki" }, { id: 2, code: "sin_nombre" }, { id: 3 }],
      [{ id: 1, name: "Reiki" }],
    );
    expect(options).toEqual([
      { id: 3, name: "3" },
      { id: 1, name: "Reiki" },
      { id: 2, name: "sin_nombre" },
    ]);
  });

  it("sorts by Spanish rules (accents do not push a name to the end)", () => {
    const names = ["Zaragoza", "Álava", "Badajoz", "Ávila", "Albacete"];
    const options = buildOptions(
      names.map((_, index) => ({ id: index + 1 })),
      names.map((name, index) => ({ id: index + 1, name })),
    );
    expect(options.map((option) => option.name)).toEqual(["Álava", "Albacete", "Ávila", "Badajoz", "Zaragoza"]);
  });

  it("is stable for equal names (by id) and handles an empty list", () => {
    expect(buildOptions([{ id: 9 }, { id: 4 }], [{ id: 9, name: "Igual" }, { id: 4, name: "Igual" }]).map((o) => o.id)).toEqual([4, 9]);
    expect(buildOptions([], [])).toEqual([]);
  });
});

describe("buildOptions with listed-first codes", () => {
  const items = [{ id: 1, code: "reiki" }, { id: 2, code: "lnt_schwiderski" }, { id: 3, code: "akashic" }, { id: 4, code: "otra" }];
  const names = [
    { id: 1, name: "Reiki" }, { id: 2, name: "LNT® - La Nueva Terapia - Método Schwiderski" },
    { id: 3, name: "Registros akáshicos" }, { id: 4, name: "Aromaterapia" },
  ];

  it("puts the listed-first codes before the alphabetical rest", () => {
    expect(buildOptions(items, names, ["lnt_schwiderski"]).map((o) => o.id)).toEqual([2, 4, 3, 1]);
  });

  it("respects the order of the list when there are several", () => {
    expect(buildOptions(items, names, ["reiki", "lnt_schwiderski"]).map((o) => o.id)).toEqual([1, 2, 4, 3]);
  });

  it("an unknown code in the list changes nothing; no list means fully alphabetical", () => {
    expect(buildOptions(items, names, ["no_existe"]).map((o) => o.id)).toEqual([4, 2, 3, 1]);
    expect(buildOptions(items, names).map((o) => o.id)).toEqual([4, 2, 3, 1]);
  });

  it("the site lists LNT first today", () => {
    expect(THERAPIES_LISTED_FIRST).toEqual(["lnt_schwiderski"]);
  });
});

describe("listTherapies", () => {
  it("reads each table on its own (no nested join) and merges the Spanish names", async () => {
    const { client, calls } = fakeClient({
      languages: [{ id: 1 }],
      therapies: [{ id: 10, code: "reiki" }, { id: 11, code: "biodescodificacion" }, { id: 12, code: "lnt_schwiderski" }],
      therapy_translations: [
        { therapy_id: 10, name: "Reiki" },
        { therapy_id: 11, name: "Biodescodificación" },
        { therapy_id: 12, name: "LNT® - La Nueva Terapia - Método Schwiderski" },
      ],
    });
    const result = await listTherapies(client);
    expect(result).toEqual([
      { id: 12, name: "LNT® - La Nueva Terapia - Método Schwiderski" },
      { id: 11, name: "Biodescodificación" },
      { id: 10, name: "Reiki" },
    ]);
    expect(calls.map((call) => call.table)).toEqual(["languages", "therapies", "therapy_translations"]);
    // explicit limit on every read / límite explícito en cada lectura
    expect(calls.every((call) => call.steps.some(([method]) => method === "limit"))).toBe(true);
  });

  it("returns an empty list without asking for names when there are no therapies", async () => {
    const { client, calls } = fakeClient({ languages: [{ id: 1 }], therapies: [] });
    expect(await listTherapies(client)).toEqual([]);
    expect(calls.map((call) => call.table)).toEqual(["languages", "therapies"]);
  });

  it("fails clearly when the language is missing or a read errors", async () => {
    await expect(listTherapies(fakeClient({ languages: [] }).client)).rejects.toThrow(/not found/);
    await expect(listTherapies(fakeClient({ languages: { error: "boom" } }).client)).rejects.toThrow(/Could not read/);
  });
});

describe("listLocations", () => {
  it("lists countries with parent_id IS NULL", async () => {
    const { client, calls } = fakeClient({
      languages: [{ id: 1 }],
      locations: [{ id: 1 }, { id: 2 }],
      location_translations: [
        { location_id: 1, name: "Argentina" },
        { location_id: 2, name: "España" },
      ],
    });
    expect(await listLocations(client, null)).toEqual([
      { id: 1, name: "Argentina" },
      { id: 2, name: "España" },
    ]);
    const locationCall = calls.find((call) => call.table === "locations");
    expect(locationCall?.steps).toContainEqual(["is", "parent_id", null]);
  });

  it("lists the children of a place with parent_id = id", async () => {
    const { client, calls } = fakeClient({
      languages: [{ id: 1 }],
      locations: [{ id: 5 }],
      location_translations: [{ location_id: 5, name: "Neuquén" }],
    });
    expect(await listLocations(client, 1)).toEqual([{ id: 5, name: "Neuquén" }]);
    const locationCall = calls.find((call) => call.table === "locations");
    expect(locationCall?.steps).toContainEqual(["eq", "parent_id", 1]);
  });
});
