// Health notice for visitors: what the site is and is not. One place, so every page says the same thing.
// Aviso de salud para visitantes: qué es y qué no es el sitio. Un solo lugar, así todas las páginas dicen lo mismo.

import Link from "next/link";

export function HealthNotice({ className = "" }: { className?: string }) {
  return (
    <aside aria-label="Aviso sobre salud" className={`border-t border-linea pt-4 text-sm text-apagado ${className}`}>
      <p>Este sitio solo conecta personas con terapeutas: no da turnos ni cobra, y no garantiza resultados.</p>
      <p className="mt-1">
        <strong className="font-semibold text-tinta">No sustituye tratamientos médicos ni psicológicos.</strong> Bajo ningún concepto debés
        abandonar un tratamiento, ni siquiera si un terapeuta te lo indica; si alguno te lo pide, denunciá su perfil.
      </p>
      <p className="mt-1">
        Desconfiá de quien prometa curas o sanaciones.{" "}
        <Link href="/legal/aviso-legal" className="underline">Más información</Link>
      </p>
    </aside>
  );
}
