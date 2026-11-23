// Finding a therapy of the catalog by the name a person typed (pure code). / Buscar una terapia del catálogo por el nombre escrito (código puro).

import { describe, expect, it } from "vitest";
import { findExistingTherapy } from "@/lib/therapy-match";

const OPTIONS = [{ id: 8, name: "Hipnoterapia" }, { id: 10, name: "Reiki" }, { id: 11, name: "Meditación y Mindfulness" }];

describe("findExistingTherapy", () => {
  it("matches the same name ignoring accents, capitals and extra spaces", () => {
    expect(findExistingTherapy(OPTIONS, "hipnoterapia")?.id).toBe(8);
    expect(findExistingTherapy(OPTIONS, "  REIKI ")?.id).toBe(10);
    expect(findExistingTherapy(OPTIONS, "meditacion   y mindfulness")?.id).toBe(11);
  });
  it("never matches a part of a name, and empty text matches nothing", () => {
    expect(findExistingTherapy(OPTIONS, "Hipno")).toBeNull();
    expect(findExistingTherapy(OPTIONS, "Reiki Usui")).toBeNull();
    expect(findExistingTherapy(OPTIONS, "   ")).toBeNull();
    expect(findExistingTherapy([], "Reiki")).toBeNull();
  });
});
