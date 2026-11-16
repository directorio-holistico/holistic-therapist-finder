import sharp from "sharp";
import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { processPhoto } = await import("@/lib/photo-process");

async function picture(width: number, height: number, format: "jpeg" | "png" | "webp" = "jpeg", withExif = false): Promise<Buffer> {
  let image = sharp({ create: { width, height, channels: 3, background: { r: 200, g: 120, b: 60 } } });
  if (withExif) image = image.withExif({ IFD0: { Copyright: "secret-camera", Make: "SecretMake" } });
  return image.toFormat(format).toBuffer();
}

describe("processPhoto", () => {
  it("makes a 512 x 512 JPEG from a landscape picture / hace un JPEG de 512 x 512 desde una foto apaisada", async () => {
    const result = await processPhoto(await picture(900, 600));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const meta = await sharp(result.jpeg).metadata();
    expect([meta.format, meta.width, meta.height]).toEqual(["jpeg", 512, 512]);
  });
  it("accepts PNG and WebP and always answers JPEG / acepta PNG y WebP y siempre devuelve JPEG", async () => {
    for (const format of ["png", "webp"] as const) {
      const result = await processPhoto(await picture(600, 600, format));
      expect(result.ok).toBe(true);
      if (result.ok) expect((await sharp(result.jpeg).metadata()).format).toBe("jpeg");
    }
  });
  it("drops the metadata (camera, GPS) / descarta los metadatos (cámara, GPS)", async () => {
    const source = await picture(600, 600, "jpeg", true);
    expect((await sharp(source).metadata()).exif).toBeDefined();
    const result = await processPhoto(source);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const meta = await sharp(result.jpeg).metadata();
    expect(meta.exif).toBeUndefined();
    expect(result.jpeg.includes(Buffer.from("secret-camera"))).toBe(false);
  });
  it("refuses a picture that is too small / rechaza una imagen muy chica", async () => {
    expect(await processPhoto(await picture(100, 100))).toEqual({ ok: false, reason: "size" });
    expect(await processPhoto(await picture(2000, 200))).toEqual({ ok: false, reason: "size" });
  });
  it("refuses empty and oversized files / rechaza archivos vacíos y demasiado pesados", async () => {
    expect(await processPhoto(Buffer.alloc(0))).toEqual({ ok: false, reason: "size" });
    expect(await processPhoto(Buffer.alloc(1_000_001, 1))).toEqual({ ok: false, reason: "size" });
  });
  it("refuses what is not a picture and formats outside the list / rechaza lo que no es imagen y formatos fuera de la lista", async () => {
    expect(await processPhoto(Buffer.from("<html>not a picture</html>"))).toEqual({ ok: false, reason: "unreadable" });
    expect(await processPhoto(await picture(600, 600, "jpeg").then((b) => sharp(b).gif().toBuffer()))).toEqual({ ok: false, reason: "format" });
  });
  it("turns transparent areas white, not black / lo transparente queda blanco, no negro", async () => {
    const transparent = await sharp({ create: { width: 600, height: 600, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
    const result = await processPhoto(transparent);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const { data } = await sharp(result.jpeg).raw().toBuffer({ resolveWithObject: true });
    expect(data[0]).toBeGreaterThan(240);
  });
});
