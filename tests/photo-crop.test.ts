import { describe, expect, it } from "vitest";
import { baseScale, CROP_OUTPUT, CROP_VIEW, drawRect, normalizeCrop, ZOOM_MAX } from "@/lib/photo-crop";

describe("baseScale", () => {
  it("the shorter side fills the window / el lado corto llena la ventana", () => {
    expect(baseScale(1000, 500)).toBeCloseTo(CROP_VIEW / 500);
    expect(baseScale(400, 800)).toBeCloseTo(CROP_VIEW / 400);
  });
});

describe("normalizeCrop", () => {
  it("a square picture at zoom 1 cannot move / una imagen cuadrada con zoom 1 no se puede mover", () => {
    expect(normalizeCrop(600, 600, { zoom: 1, x: 50, y: -50 })).toEqual({ zoom: 1, x: 0, y: 0 });
  });
  it("a landscape picture moves only sideways, up to its edge / una apaisada solo se mueve de costado, hasta su borde", () => {
    const crop = normalizeCrop(1000, 500, { zoom: 1, x: 9999, y: 9999 });
    expect(crop.y).toBe(0);
    expect(crop.x).toBeCloseTo((1000 * (CROP_VIEW / 500) - CROP_VIEW) / 2);
  });
  it("zooming allows moving in both directions / el zoom permite moverse en ambos sentidos", () => {
    const crop = normalizeCrop(600, 600, { zoom: 2, x: -9999, y: 9999 });
    expect(crop.x).toBeCloseTo(-CROP_VIEW / 2);
    expect(crop.y).toBeCloseTo(CROP_VIEW / 2);
  });
  it("keeps the zoom between 1 and the maximum and ignores broken numbers / mantiene el zoom entre 1 y el máximo e ignora números rotos", () => {
    expect(normalizeCrop(600, 600, { zoom: 0.2, x: 0, y: 0 }).zoom).toBe(1);
    expect(normalizeCrop(600, 600, { zoom: 99, x: 0, y: 0 }).zoom).toBe(ZOOM_MAX);
    expect(normalizeCrop(600, 600, { zoom: Number.NaN, x: Number.NaN, y: 0 })).toEqual({ zoom: 1, x: 0, y: 0 });
  });
});

describe("drawRect", () => {
  it("a centred square at zoom 1 fills the whole output / un cuadrado centrado con zoom 1 llena toda la salida", () => {
    const rect = drawRect(800, 800, { zoom: 1, x: 0, y: 0 });
    expect(rect.dx).toBeCloseTo(0);
    expect(rect.dy).toBeCloseTo(0);
    expect(rect.dw).toBeCloseTo(CROP_OUTPUT);
    expect(rect.dh).toBeCloseTo(CROP_OUTPUT);
  });
  it("the picture always covers the output square / la imagen siempre cubre el cuadrado de salida", () => {
    for (const [w, h] of [[1000, 500], [500, 1000], [640, 640]] as const) {
      for (const crop of [{ zoom: 1, x: 500, y: 500 }, { zoom: 2.5, x: -500, y: 300 }, { zoom: 3, x: 0, y: 0 }]) {
        const r = drawRect(w, h, crop);
        expect(r.dx).toBeLessThanOrEqual(1e-6);
        expect(r.dy).toBeLessThanOrEqual(1e-6);
        expect(r.dx + r.dw).toBeGreaterThanOrEqual(CROP_OUTPUT - 1e-6);
        expect(r.dy + r.dh).toBeGreaterThanOrEqual(CROP_OUTPUT - 1e-6);
      }
    }
  });
});
