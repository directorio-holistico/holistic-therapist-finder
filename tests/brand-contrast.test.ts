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

  it("keeps the 12 star colours as valid hex values", () => {
    expect(STAR_DOT_COLORS).toHaveLength(12);
    for (const c of STAR_DOT_COLORS) expect(c).toMatch(/^#[0-9A-F]{6}$/);
  });
});
