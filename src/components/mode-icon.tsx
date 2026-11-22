// Small icons for how a therapy is given: in person (map pin) or remote (screen). They are decoration: the text always goes
// with them (a screen reader reads the text, never the icon).
// Iconos chicos para cómo se da una terapia: presencial (marcador de mapa) o a distancia (pantalla). Son decoración: el texto
// siempre va con ellos (el lector de pantalla lee el texto, nunca el ícono).

import { labelServiceMode } from "@/lib/labels";

function Icon({ mode, className, size = 16 }: { mode: string; className?: string; size?: number }) {
  const common = {
    xmlns: "http://www.w3.org/2000/svg",
    viewBox: "0 0 24 24",
    width: size,
    height: size,
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
    className,
  };
  if (mode === "remote") {
    return (
      <svg {...common}>
        <rect x="3" y="4" width="18" height="12" rx="2" />
        <path d="M8 20h8M12 16v4" />
      </svg>
    );
  }
  return (
    <svg {...common}>
      <path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z" />
      <circle cx="12" cy="10" r="2.5" />
    </svg>
  );
}

// The one round icon used everywhere (cards, profile, legend), so it looks the same in all of them.
// El único ícono redondo que se usa en todos lados (tarjetas, perfil, leyenda), así se ve igual en todos.
function RoundIcon({ mode, compact = false }: { mode: string; compact?: boolean }) {
  return (
    <span aria-hidden="true" className={`inline-flex shrink-0 items-center justify-center rounded-full bg-fondo text-tinta ring-1 ring-linea ${compact ? "size-7" : "size-9"}`}>
      <Icon mode={mode} size={compact ? 16 : 18} />
    </span>
  );
}

// Icon plus text (profile, search form). "compact" is the smaller circle for the search form. / Ícono más texto (perfil, buscador). "compact" es el círculo más chico del buscador.
export function ModeBadge({ mode, compact = false }: { mode: string; compact?: boolean }) {
  return (
    <span className={`inline-flex items-center text-sm text-tinta ${compact ? "gap-1.5" : "gap-2"}`}>
      <RoundIcon mode={mode} compact={compact} />
      {labelServiceMode(mode)}
    </span>
  );
}

// Icon only, for cards: the label stays for screen readers and as a tooltip. / Solo ícono, para tarjetas: el texto queda para lectores de pantalla y como ayuda al pasar el mouse.
export function ModeIcon({ mode }: { mode: string }) {
  const label = labelServiceMode(mode);
  return (
    <span title={label} className="inline-flex">
      <RoundIcon mode={mode} />
      <span className="sr-only">{label}</span>
    </span>
  );
}
