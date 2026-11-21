"use client";

// Shown when the search cannot reach the database (for example, a paused free-plan project).
// Se muestra cuando la búsqueda no llega a la base (por ejemplo, un proyecto del plan gratis en pausa).

export default function SearchError({ retry }: { error: unknown; retry: () => void }) {
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-10">
      <h1 className="font-display text-3xl font-semibold text-tinta">No pudimos cargar la búsqueda</h1>
      <p className="mt-2 text-apagado">Probá de nuevo en unos minutos.</p>
      <button
        type="button"
        onClick={() => retry()}
        className="mt-4 inline-flex min-h-11 items-center justify-center rounded-full border border-tinta px-5 text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
      >
        Reintentar
      </button>
    </main>
  );
}
