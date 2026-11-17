"use client";

import "./globals.css";

// Last safety net: it replaces the ROOT layout when that layout itself fails, so it must bring its own <html> and <body>.
// Plain and short on purpose: it must not depend on anything that could be the cause of the failure.
// Último respaldo: reemplaza el layout RAÍZ cuando falla ese mismo layout, por eso trae su propio <html> y <body>.
// Simple y corto a propósito: no debe depender de nada que pueda ser la causa de la falla.

export default function GlobalError({ retry }: { error: unknown; retry: () => void }) {
  return (
    <html lang="es" data-theme="claro">
      <body className="min-h-full flex flex-col items-center justify-center px-6 py-16 text-center">
        <h1 className="font-display text-4xl font-semibold text-tinta">Algo salió mal</h1>
        <p className="mt-4 text-lg text-apagado">No pudimos mostrar el sitio. Probá de nuevo en unos minutos.</p>
        <button
          type="button"
          onClick={() => retry()}
          className="mt-8 inline-flex min-h-12 items-center rounded-full bg-boton px-7 text-base font-semibold text-boton-texto hover:opacity-90"
        >
          Reintentar
        </button>
      </body>
    </html>
  );
}
