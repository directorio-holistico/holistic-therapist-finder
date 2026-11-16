// Re-encodes the uploaded picture on the server: checks that it is a real JPEG, PNG or WebP of a sensible size, cuts a centered
// square of 512 px and writes a new JPEG WITHOUT metadata (no GPS position, no camera data). The browser already did the crop the
// therapist chose; this step does not trust it.
// Recodifica en el servidor la imagen subida: comprueba que sea un JPEG, PNG o WebP real de tamaño razonable, corta un cuadrado
// centrado de 512 px y escribe un JPEG nuevo SIN metadatos (sin posición GPS ni datos de la cámara). El navegador ya hizo el
// recorte que eligió el terapeuta; este paso no confía en él.

import "server-only";
import sharp from "sharp";
import { PHOTO_ALLOWED_FORMATS, PHOTO_MAX_INPUT_PIXELS, PHOTO_MAX_UPLOAD_BYTES, PHOTO_MIN_SIDE, PHOTO_OUTPUT_SIZE } from "@/lib/photo-rules";

export type ProcessedPhoto = { ok: true; jpeg: Buffer } | { ok: false; reason: "format" | "size" | "unreadable" };

export async function processPhoto(input: Buffer): Promise<ProcessedPhoto> {
  if (input.length === 0 || input.length > PHOTO_MAX_UPLOAD_BYTES) return { ok: false, reason: "size" };
  try {
    const image = sharp(input, { limitInputPixels: PHOTO_MAX_INPUT_PIXELS, failOn: "error" });
    const meta = await image.metadata();
    if (!meta.format || !(PHOTO_ALLOWED_FORMATS as readonly string[]).includes(meta.format)) return { ok: false, reason: "format" };
    if (!meta.width || !meta.height || Math.min(meta.width, meta.height) < PHOTO_MIN_SIDE) return { ok: false, reason: "size" };
    // sharp drops all metadata unless asked to keep it: nothing is asked here. / sharp descarta todos los metadatos salvo que se le pida conservarlos: acá no se pide.
    const jpeg = await image
      .rotate()
      .resize(PHOTO_OUTPUT_SIZE, PHOTO_OUTPUT_SIZE, { fit: "cover", position: "centre" })
      .flatten({ background: "#ffffff" }) // transparent areas become white, not black / lo transparente queda blanco, no negro
      .jpeg({ quality: 85, mozjpeg: true })
      .toBuffer();
    return { ok: true, jpeg };
  } catch {
    return { ok: false, reason: "unreadable" };
  }
}
