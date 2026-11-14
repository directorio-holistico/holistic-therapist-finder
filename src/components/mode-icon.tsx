// Small icons for how a therapy is given: in person (map pin) or remote (screen). They are decoration: the text always goes
// with them (a screen reader reads the text, never the icon).
// Iconos chicos para cómo se da una terapia: presencial (marcador de mapa) o a distancia (pantalla). Son decoración: el texto
// siempre va con ellos (el lector de pantalla lee el texto, nunca el ícono).

import { labelServiceMode } from "@/lib/labels";

function Icon({ mode, className }: { mode: string; className?: string }) {
  const common = {
    xmlns: "http://www.w3.org/2000/svg",
    viewBox: "0 0 24 24",
    width: 16,
    height: 16,
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
    <span className="inline-flex items-center gap-1 rounded-full border border-zinc-300 px-2 py-0.5 text-sm text-zinc-800 dark:border-zinc-600 dark:text-zinc-200">
      <Icon mode={mode} />
      {labelServiceMode(mode)}
    </span>
  );
}
