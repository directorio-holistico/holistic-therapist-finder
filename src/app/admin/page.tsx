// Admin home: what is waiting for a decision. / Inicio de administración: lo que espera una decisión.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { loadFollowUpStubs } from "@/lib/admin/followup";

async function Summary() {
  const { supabase } = await requireAdmin();
  const pending = await supabase.from("revision_statuses").select("id").eq("code", "pending_review").maybeSingle();
  if (pending.error || !pending.data) throw new Error("Could not read the revision statuses / No se pudieron leer los estados de revisión");
  const count = await supabase.from("profile_revisions").select("id", { count: "exact", head: true }).eq("status_id", pending.data.id);
  if (count.error) throw new Error(`Could not count the revisions / No se pudieron contar las revisiones: ${count.error.message}`);
  return (
    <section className="mt-6 rounded-xl border border-linea bg-superficie p-5">
      <h2 className="font-display text-xl font-semibold text-tinta">Revisiones de perfiles</h2>
      <p className="mt-1 text-apagado">
        {count.count === 0 ? "No hay revisiones esperando." : `Esperando una decisión: ${count.count}.`}
      </p>
      <Link href="/admin/revisiones" className="mt-4 inline-flex min-h-11 items-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">
        Ver revisiones
      </Link>
    </section>
  );
}

async function ReportsSummary() {
  const { supabase } = await requireAdmin();
  const open = await supabase.from("report_statuses").select("id").eq("code", "open").maybeSingle();
  if (open.error || !open.data) throw new Error("Could not read the report statuses / No se pudieron leer los estados de denuncias");
  const count = await supabase.from("reports").select("id", { count: "exact", head: true }).eq("status_id", open.data.id);
  if (count.error) throw new Error(`Could not count the reports / No se pudieron contar las denuncias: ${count.error.message}`);
  return (
    <section className="mt-6 rounded-xl border border-linea bg-superficie p-5">
      <h2 className="font-display text-xl font-semibold text-tinta">Denuncias de perfiles</h2>
      <p className="mt-1 text-apagado">
        {count.count === 0 ? "No hay denuncias abiertas." : `Abiertas: ${count.count}.`}
      </p>
      <Link href="/admin/denuncias" className="mt-4 inline-flex min-h-11 items-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">
        Ver denuncias
      </Link>
    </section>
  );
}

async function FollowUpSummary() {
  const { supabase } = await requireAdmin();
  const { rejected, drafts } = await loadFollowUpStubs(supabase);
  return (
    <section className="mt-6 rounded-xl border border-linea bg-superficie p-5">
      <h2 className="font-display text-xl font-semibold text-tinta">Seguimiento de terapeutas</h2>
      <p className="mt-1 text-apagado">
        {rejected.length === 0 && drafts.length === 0
          ? "Nadie está esperando una respuesta."
          : `Rechazos sin respuesta: ${rejected.length}. Borradores sin enviar: ${drafts.length}.`}
      </p>
      <Link href="/admin/seguimiento" className="mt-4 inline-flex min-h-11 items-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">
        Ver seguimiento
      </Link>
    </section>
  );
}

export default function AdminHome() {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Administración</h1>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <Summary />
      </Suspense>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <ReportsSummary />
      </Suspense>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <FollowUpSummary />
      </Suspense>
    </main>
  );
}
