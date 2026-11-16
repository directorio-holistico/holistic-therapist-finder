import { describe, expect, it } from "vitest";
import { isPendingPhotoPath, pendingPhotoPath, photoChangeOf, PHOTO_CONSENT_TEXT, PHOTO_CONSENT_VERSION } from "@/lib/photo-rules";

const PROFILE = "773f2832-c09f-4878-98e4-98bf190bff2c";
const OTHER = "276ff3e7-f824-4e24-b6a8-ab6138b2019b";
const FILE = "0b8f6f0e-1c2d-4e3f-8a9b-0c1d2e3f4a5b";

describe("pendingPhotoPath", () => {
  it("joins the profile id and the file id / une el id del perfil y el del archivo", () => {
    expect(pendingPhotoPath(PROFILE, FILE)).toBe(`${PROFILE}/${FILE}.jpg`);
  });
  it("lowercases and refuses anything that is not a uuid / pasa a minúsculas y rechaza lo que no sea uuid", () => {
    expect(pendingPhotoPath(PROFILE.toUpperCase(), FILE)).toBe(`${PROFILE}/${FILE}.jpg`);
    expect(pendingPhotoPath("../x", FILE)).toBeNull();
    expect(pendingPhotoPath(PROFILE, "avatar")).toBeNull();
  });
});

describe("isPendingPhotoPath", () => {
  it("accepts only a path inside the own profile folder / acepta solo una ruta dentro de la carpeta del propio perfil", () => {
    expect(isPendingPhotoPath(`${PROFILE}/${FILE}.jpg`, PROFILE)).toBe(true);
    expect(isPendingPhotoPath(`${OTHER}/${FILE}.jpg`, PROFILE)).toBe(false);
  });
  it("refuses traversal, other names, other extensions and non-strings / rechaza recorridos, otros nombres, extensiones y no-texto", () => {
    for (const bad of [`${PROFILE}/../${OTHER}/${FILE}.jpg`, `${PROFILE}/avatar.jpg`, `${PROFILE}/${FILE}.png`, `${PROFILE}/${FILE}.jpg/x`, `/${PROFILE}/${FILE}.jpg`, "", null, undefined, 3]) {
      expect(isPendingPhotoPath(bad, PROFILE)).toBe(false);
    }
  });
  it("refuses a profile id that is not a uuid / rechaza un id de perfil que no es uuid", () => {
    expect(isPendingPhotoPath(`${PROFILE}/${FILE}.jpg`, "nope")).toBe(false);
  });
});

describe("photoChangeOf", () => {
  it("absent key = no change / clave ausente = sin cambio", () => {
    expect(photoChangeOf({ headline: "x" })).toEqual({ kind: "none" });
    expect(photoChangeOf(null)).toEqual({ kind: "none" });
    expect(photoChangeOf("text")).toEqual({ kind: "none" });
  });
  it("a path = new photo, null = remove / una ruta = foto nueva, null = quitar", () => {
    expect(photoChangeOf({ photo_path: `${PROFILE}/${FILE}.jpg` })).toEqual({ kind: "set", path: `${PROFILE}/${FILE}.jpg` });
    expect(photoChangeOf({ photo_path: null })).toEqual({ kind: "remove" });
  });
  it("an empty or odd value is no change / un valor vacío o raro es sin cambio", () => {
    expect(photoChangeOf({ photo_path: "" })).toEqual({ kind: "none" });
    expect(photoChangeOf({ photo_path: 5 })).toEqual({ kind: "none" });
  });
});

describe("consent", () => {
  it("the version fits the rule of the database / la versión cumple la regla de la base", () => {
    expect(PHOTO_CONSENT_VERSION).toMatch(/^[A-Za-z0-9._-]{1,40}$/);
  });
  it("the text says whose photo it is and that it can be withdrawn / el texto dice de quién es la foto y que se puede retirar", () => {
    expect(PHOTO_CONSENT_TEXT).toMatch(/es mía/);
    expect(PHOTO_CONSENT_TEXT).toMatch(/retirar/);
  });
});
