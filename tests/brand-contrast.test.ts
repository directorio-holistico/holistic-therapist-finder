import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { STAR_DOT_COLORS } from "@/lib/brand";

const css = readFileSync(join(process.cwd(), "src/app/globals.css"), "utf8");

function block(selector: string): Record<string, string> {
  const start = css.indexOf(`${selector} {`);
  const end = css.indexOf("}", start);
  const vars: Record<string, string> = {};
  for (const m of css.slice(start, end).matchAll(/--([a-z-]+):\s*(#[0-9A-Fa-f]{6});/g)) {
    const [, name, value] = m;
    if (name && value) vars[name] = value;
  }
  return vars;
}

function luminance(hex: string): number {
  const lin = (i: number) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(1) + 0.7152 * lin(3) + 0.0722 * lin(5);
}

function contrast(a: string, b: string): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// Text pairs that must reach WCAG AA (4.5:1). / Pares de texto que deben llegar a WCAG AA (4,5:1).
const PAIRS: Array<[string, string]> = [
  ["tinta", "fondo"],
  ["tinta", "superficie"],
  ["apagado", "fondo"],
  ["apagado", "superficie"],
  ["acento", "fondo"],
  ["acento", "superficie"],
  ["boton-texto", "boton"],
];

// Borders of form fields are interface parts: they need 3:1 (WCAG 1.4.11). / Los bordes de campos son partes de la interfaz: necesitan 3:1 (WCAG 1.4.11).
const FIELD_PAIRS: Array<[string, string]> = [
  ["campo", "superficie"],
  ["campo", "fondo"],
];

describe("brand colours", () => {
  for (const [name, selector] of [
    ["claro", ":root"],
    ["oscuro", '[data-theme="oscuro"]'],
  ] as const) {
    const vars = block(selector);
    for (const [fg, bg] of PAIRS) {
      it(`${name}: ${fg} on ${bg} reaches 4.5:1`, () => {
        const fgColor = vars[fg];
        const bgColor = vars[bg];
        if (!fgColor || !bgColor) throw new Error(`missing --${fg} or --${bg}`);
        expect(contrast(fgColor, bgColor)).toBeGreaterThanOrEqual(4.5);
      });
    }
  }

  for (const [name, selector] of [
    ["claro", ":root"],
    ["oscuro", '[data-theme="oscuro"]'],
  ] as const) {
    const vars = block(selector);
    for (const [fg, bg] of FIELD_PAIRS) {
      it(`${name}: ${fg} on ${bg} reaches 3:1`, () => {
        const fgColor = vars[fg];
        const bgColor = vars[bg];
        if (!fgColor || !bgColor) throw new Error(`missing --${fg} or --${bg}`);
        expect(contrast(fgColor, bgColor)).toBeGreaterThanOrEqual(3);
      });
    }
  }

  // State colours: the text must be readable on its own tinted box AND on the page and card backgrounds; the border is a part of the interface (3:1).
  // Colores de estado: el texto debe leerse sobre su caja teñida Y sobre el fondo y la tarjeta; el borde es parte de la interfaz (3:1).
  for (const [name, selector] of [
    ["claro", ":root"],
    ["oscuro", '[data-theme="oscuro"]'],
  ] as const) {
    const vars = block(selector);
    for (const state of ["ok", "aviso", "peligro", "neutro"]) {
      for (const bg of [`${state}-fondo`, "fondo", "superficie"]) {
        it(`${name}: ${state}-texto on ${bg} reaches 4.5:1`, () => {
          const fgColor = vars[`${state}-texto`];
          const bgColor = vars[bg];
          if (!fgColor || !bgColor) throw new Error(`missing --${state}-texto or --${bg}`);
          expect(contrast(fgColor, bgColor)).toBeGreaterThanOrEqual(4.5);
        });
      }
      it(`${name}: ${state}-borde on fondo reaches 3:1`, () => {
        const fgColor = vars[`${state}-borde`];
        const bgColor = vars["fondo"];
        if (!fgColor || !bgColor) throw new Error(`missing --${state}-borde or --fondo`);
        expect(contrast(fgColor, bgColor)).toBeGreaterThanOrEqual(3);
      });
    }
  }

  it("keeps the 12 star colours as valid hex values", () => {
    expect(STAR_DOT_COLORS).toHaveLength(12);
    for (const c of STAR_DOT_COLORS) expect(c).toMatch(/^#[0-9A-F]{6}$/);
  });
});
