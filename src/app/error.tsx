"use client";

import Link from "next/link";
import { useEffect } from "react";

// Shown when a page fails while it renders (for example, the database does not answer). It is inside the root layout, so the
// footer stays. "retry" asks Next.js to render the segment again (stable since Next.js 16.3).
// Se muestra cuando una página falla al armarse (por ejemplo, la base no responde). Está dentro del layout raíz, así que el
// pie se mantiene. "retry" le pide a Next.js que arme el segmento de nuevo (estable desde Next.js 16.3).

export default function AppError({ error, retry }: { error: unknown; retry: () => void }) {
  useEffect(() => {
    // the browser console is enough for now; a real error service is a later decision / por ahora alcanza la consola del navegador
    console.error(error);
  }, [error]);

  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col items-center px-6 py-16 text-center">
      <h1 className="font-display text-4xl font-semibold text-tinta sm:text-5xl">Algo salió mal</h1>
      <p className="mt-4 text-lg text-apagado">No pudimos mostrar esta página. Probá de nuevo en unos minutos.</p>
      <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
        <button
          type="button"
          onClick={() => retry()}
          className="inline-flex min-h-12 items-center rounded-full bg-boton px-7 text-base font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
        >
          Reintentar
        </button>
        <Link href="/" className="inline-flex min-h-12 items-center px-2 font-medium text-tinta underline">
          Volver al inicio
        </Link>
      </div>
    </main>
  );
}
