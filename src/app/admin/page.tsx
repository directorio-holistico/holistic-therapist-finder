// Admin home: what is waiting for a decision. / Inicio de administración: lo que espera una decisión.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";

async function Summary() {
  const { supabase } = await requireAdmin();
  const pending = await supabase.from("revision_statuses").select("id").eq("code", "pending_review").maybeSingle();
  if (pending.error || !pending.data) throw new Error("Could not read the revision statuses / No se pudieron leer los estados de revisión");
  const count = await supabase.from("profile_revisions").select("id", { count: "exact", head: true }).eq("status_id", pending.data.id);
  if (count.error) throw new Error(`Could not count the revisions / No se pudieron contar las revisiones: ${count.error.message}`);
  return (
    <section className="mt-6 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
      <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Revisiones de perfiles</h2>
      <p className="mt-1 text-zinc-700 dark:text-zinc-300">
        {count.count === 0 ? "No hay revisiones esperando." : `Esperando una decisión: ${count.count}.`}
      </p>
      <Link href="/admin/revisiones" className="mt-3 inline-block rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">
        Ver revisiones
      </Link>
    </section>
  );
}

export default function AdminHome() {
  return (
    <main>
      <h1 className="mt-6 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Administración</h1>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Summary />
      </Suspense>
    </main>
  );
}
