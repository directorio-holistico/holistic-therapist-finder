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

export function ModeBadge({ mode }: { mode: string }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full border border-linea px-2.5 py-0.5 text-sm text-tinta">
      <Icon mode={mode} />
      {labelServiceMode(mode)}
    </span>
  );
}

// Icon only, for cards: the label stays for screen readers and as a tooltip. / Solo ícono, para tarjetas: el texto queda para lectores de pantalla y como ayuda al pasar el mouse.
export function ModeIcon({ mode }: { mode: string }) {
  const label = labelServiceMode(mode);
  return (
    <span
      title={label}
      className="inline-flex size-10 items-center justify-center rounded-full bg-fondo text-tinta ring-1 ring-linea"
    >
      <Icon mode={mode} size={20} />
      <span className="sr-only">{label}</span>
    </span>
  );
}
