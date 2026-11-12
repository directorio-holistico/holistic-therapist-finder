"use client";

// Shown when the search cannot reach the database (for example, a paused free-plan project).
// Se muestra cuando la búsqueda no llega a la base (por ejemplo, un proyecto del plan gratis en pausa).

export default function SearchError({ retry }: { error: unknown; retry: () => void }) {
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">No pudimos cargar la búsqueda</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">Probá de nuevo en unos minutos.</p>
      <button
        type="button"
        onClick={() => retry()}
        className="mt-4 rounded-md border border-zinc-500 px-4 py-2 text-zinc-900 dark:text-zinc-100"
      >
        Reintentar
      </button>
    </main>
  );
}
