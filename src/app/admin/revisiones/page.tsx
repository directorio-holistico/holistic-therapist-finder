// Revisions waiting for a decision, the most urgent first. / Revisiones esperando una decisión, las más urgentes primero.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { formatDate } from "@/lib/format";

const RESULTS: Record<string, string> = { aprobada: "La revisión fue aprobada.", rechazada: "La revisión fue rechazada." };

async function List({ searchParams }: { searchParams: Promise<{ resultado?: string | string[] }> }) {
  const { supabase } = await requireAdmin();
  const { resultado } = await searchParams;
  const notice = typeof resultado === "string" ? RESULTS[resultado] : undefined;

  const pending = await supabase.from("revision_statuses").select("id").eq("code", "pending_review").maybeSingle();
  if (pending.error || !pending.data) throw new Error("Could not read the revision statuses / No se pudieron leer los estados de revisión");
  const rows = await supabase
    .from("profile_revisions")
    .select("id, payload, flagged_terms, is_priority, submitted_at, due_at")
    .eq("status_id", pending.data.id)
    .order("is_priority", { ascending: false })
    .order("due_at", { ascending: true })
    .limit(100);
  if (rows.error) throw new Error(`Could not read the revisions / No se pudieron leer las revisiones: ${rows.error.message}`);

  const nameOf = (payload: unknown): string => {
    const value = typeof payload === "object" && payload !== null && "display_name" in payload ? payload.display_name : null;
    return typeof value === "string" && value !== "" ? value : "Sin nombre";
  };

  return (
    <>
      {notice && <p role="status" className="mt-4 rounded-md border border-green-600 bg-green-50 p-3 text-green-900">{notice}</p>}
      {rows.data.length === 0 ? (
        <p className="mt-4 text-zinc-700 dark:text-zinc-300">No hay revisiones esperando.</p>
      ) : (
        <ul className="mt-4 grid gap-3">
          {rows.data.map((row) => (
            <li key={row.id} className="rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
              <Link href={`/admin/revisiones/${row.id}`} className="text-lg font-semibold underline text-zinc-900 dark:text-zinc-100">{nameOf(row.payload)}</Link>
              <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">
                Enviada el {formatDate(row.submitted_at) ?? "—"} · responder antes del {formatDate(row.due_at) ?? "—"}
                {row.is_priority ? " · prioritaria" : ""}
              </p>
              {row.flagged_terms.length > 0 && (
                <p className="mt-1 text-sm text-amber-900">Palabras marcadas: {row.flagged_terms.length}</p>
              )}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

export default function RevisionsPage({ searchParams }: { searchParams: Promise<{ resultado?: string | string[] }> }) {
  return (
    <main>
      <h1 className="mt-6 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Revisiones pendientes</h1>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <List searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
