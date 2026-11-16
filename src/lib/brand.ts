// The 12 colours of the Camino Doce Doce star, sampled from the logo, clockwise from the top right.
// Los 12 colores de la estrella de Camino Doce Doce, tomados del logo, en sentido horario desde arriba a la derecha.
export const STAR_DOT_COLORS = [
  "#FE0000",
  "#FF6600",
  "#FEF200",
  "#4CB050",
  "#6395EC",
  "#012E67",
  "#590098",
  "#BEE3DB",
  "#089090",
  "#F7F6F1",
  "#FF9A66",
  "#D3AF37",
] as const;

export const BRAND_NAME = "Camino Doce Doce";

/** Hard-stop conic gradient with the 12 star colours, used as the ring of an avatar. / Degradé cónico con los 12 colores de la estrella, usado como aro de un avatar. */
export function starRingGradient(): string {
  const step = 360 / STAR_DOT_COLORS.length;
  const stops = STAR_DOT_COLORS.map((color, i) => `${color} ${i * step}deg ${(i + 1) * step}deg`);
  return `conic-gradient(${stops.join(", ")})`;
}
