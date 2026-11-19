// The account name is saved with a capital only at the start of each name, like the display name.
// El nombre de la cuenta se guarda con mayúscula solo al inicio de cada nombre, igual que el nombre visible.

import { describe, expect, it } from "vitest";
import { readRegistrationForm } from "@/lib/registration";

function form(fullName: string): FormData {
  const data = new FormData();
  data.set("fullName", fullName);
  data.set("terms", "on");
  data.set("privacy", "on");
  data.set("legalDeclaration", "on");
  return data;
}

describe("registration full name / nombre completo del alta", () => {
  it("lowers an all-caps name / baja un nombre todo en mayúsculas", () => {
    const parsed = readRegistrationForm(form("  ANA MARIA   PEREZ "));
    expect(parsed.success && parsed.data.fullName).toBe("Ana Maria Perez");
  });

  it("keeps link words in lowercase / deja las palabras de enlace en minúscula", () => {
    const parsed = readRegistrationForm(form("maría de los ángeles"));
    expect(parsed.success && parsed.data.fullName).toBe("María de los Ángeles");
  });

  it("still rejects an empty name / sigue rechazando un nombre vacío", () => {
    expect(readRegistrationForm(form("   ")).success).toBe(false);
  });
});
