import { describe, expect, it } from "vitest";
import { PHOTO_BUCKET, photoPublicUrl } from "@/lib/photo";

const BASE = "https://abcdefghij.supabase.co";
const ID = "0b8f6f0e-1c2d-4e3f-8a9b-0c1d2e3f4a5b";

describe("photoPublicUrl", () => {
  it("builds the public address for a clean path / arma la dirección pública para una ruta limpia", () => {
    expect(photoPublicUrl(BASE, `${ID}/avatar.jpg`)).toBe(`${BASE}/storage/v1/object/public/${PHOTO_BUCKET}/${ID}/avatar.jpg`);
  });
  it("uses only the origin of the project address / usa solo el origen de la dirección del proyecto", () => {
    expect(photoPublicUrl(`${BASE}/rest/v1/`, `${ID}/a.webp`)).toBe(`${BASE}/storage/v1/object/public/${PHOTO_BUCKET}/${ID}/a.webp`);
  });
  it("returns null without a path / devuelve null sin ruta", () => {
    expect(photoPublicUrl(BASE, null)).toBeNull();
    expect(photoPublicUrl(BASE, undefined)).toBeNull();
    expect(photoPublicUrl(BASE, "")).toBeNull();
  });
  it("rejects paths outside the profile folder rule / rechaza rutas que rompen la regla de carpeta", () => {
    expect(photoPublicUrl(BASE, "avatar.jpg")).toBeNull();
    expect(photoPublicUrl(BASE, `${ID}/../other/a.jpg`)).toBeNull();
    expect(photoPublicUrl(BASE, `${ID}/a b.jpg`)).toBeNull();
    expect(photoPublicUrl(BASE, `https://evil.example/${ID}/a.jpg`)).toBeNull();
    expect(photoPublicUrl(BASE, `${ID}/a.jpg?x=1`)).toBeNull();
  });
  it("returns null for a broken project address / devuelve null si la dirección del proyecto está mal", () => {
    expect(photoPublicUrl("not a url", `${ID}/a.jpg`)).toBeNull();
  });
});
