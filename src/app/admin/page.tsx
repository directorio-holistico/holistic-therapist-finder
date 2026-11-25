// Admin home: what is waiting for a decision. Each tile IS the link (no separate button) and says little: a title and the numbers.
// A tile turns amber when something is waiting, and the number is always written too (colour never carries the meaning alone).
// Inicio de administración: lo que espera una decisión. Cada recuadro ES el enlace (sin botón aparte) y dice poco: un título y los números.
// Un recuadro se pone ámbar cuando hay algo esperando, y el número siempre está escrito también (el color nunca lleva solo el significado).

import Link from "next/link";
import type { ReactNode } from "react";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { loadFollowUpStubs } from "@/lib/admin/followup";

const TILE_BASE = "flex min-h-36 flex-col items-center justify-center gap-2 rounded-2xl border p-4 text-center shadow-sm";
const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";

// Decorative icons (the title always goes with them). / Íconos decorativos (el título siempre los acompaña).
function Icon({ children }: { children: ReactNode }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width={26} height={26} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      {children}
    </svg>
  );
}
const ReviewsIcon = () => (
  <Icon>
    <rect x="8" y="3" width="8" height="4" rx="1" />
    <path d="M16 5h2a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2" />
    <path d="m9 14 2 2 4-4" />
  </Icon>
);
const ReportsIcon = () => (
  <Icon>
    <path d="M5 21V4" />
    <path d="M5 4h11l-2 4 2 4H5" />
  </Icon>
);
const FollowUpIcon = () => (
  <Icon>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 7v5l3 2" />
  </Icon>
);
const TherapiesIcon = () => (
  <Icon>
    <path d="M8 6h13M8 12h13M8 18h13" />
    <path d="M3 6h.01M3 12h.01M3 18h.01" />
  </Icon>
);

function Tile({ href, title, icon, attention = false, children }: { href: string; title: string; icon: ReactNode; attention?: boolean; children: ReactNode }) {
  const look = attention ? "border-aviso-borde bg-aviso-fondo text-aviso-texto" : "border-linea bg-superficie text-tinta";
  return (
    <Link href={href} className={`${TILE_BASE} ${look} motion-safe:transition-shadow hover:shadow-md ${FOCUS}`}>
      <span aria-hidden="true" className="inline-flex size-12 items-center justify-center rounded-full bg-fondo text-tinta ring-1 ring-linea">{icon}</span>
      <span className="font-display text-xl font-semibold">{title}</span>
      <span className={`text-sm ${attention ? "" : "text-apagado"}`}>{children}</span>
    </Link>
  );
}

// Same size as a tile, so the page does not jump while the numbers load. / Del mismo tamaño que un recuadro, así la página no salta mientras cargan los números.
function TileFallback() {
  return <div aria-busy="true" className={`${TILE_BASE} border-linea bg-superficie text-sm text-apagado`}>Cargando…</div>;
}

async function Summary() {
  const { supabase } = await requireAdmin();
  const pending = await supabase.from("revision_statuses").select("id").eq("code", "pending_review").maybeSingle();
  if (pending.error || !pending.data) throw new Error("Could not read the revision statuses / No se pudieron leer los estados de revisión");
  const count = await supabase.from("profile_revisions").select("id", { count: "exact", head: true }).eq("status_id", pending.data.id);
  if (count.error) throw new Error(`Could not count the revisions / No se pudieron contar las revisiones: ${count.error.message}`);
  const waiting = count.count ?? 0;
  return (
    <Tile href="/admin/revisiones" title="Revisiones" icon={<ReviewsIcon />} attention={waiting > 0}>
      En espera: {waiting}
    </Tile>
  );
}

async function ReportsSummary() {
  const { supabase } = await requireAdmin();
  const open = await supabase.from("report_statuses").select("id").eq("code", "open").maybeSingle();
  if (open.error || !open.data) throw new Error("Could not read the report statuses / No se pudieron leer los estados de denuncias");
  const count = await supabase.from("reports").select("id", { count: "exact", head: true }).eq("status_id", open.data.id);
  if (count.error) throw new Error(`Could not count the reports / No se pudieron contar las denuncias: ${count.error.message}`);
  const opened = count.count ?? 0;
  return (
    <Tile href="/admin/denuncias" title="Denuncias" icon={<ReportsIcon />} attention={opened > 0}>
      Abiertas: {opened}
    </Tile>
  );
}

async function FollowUpSummary() {
  const { supabase } = await requireAdmin();
  const { rejected, drafts } = await loadFollowUpStubs(supabase);
  return (
    <Tile href="/admin/seguimiento" title="Seguimiento" icon={<FollowUpIcon />} attention={rejected.length + drafts.length > 0}>
      Rechazos: {rejected.length} · Borradores: {drafts.length}
    </Tile>
  );
}

async function TherapiesSummary() {
  const { supabase } = await requireAdmin();
  const [active, hidden] = await Promise.all([
    supabase.from("therapies").select("id", { count: "exact", head: true }).eq("is_active", true),
    supabase.from("therapies").select("id", { count: "exact", head: true }).eq("is_active", false),
  ]);
  if (active.error || hidden.error) throw new Error("Could not count the therapies / No se pudieron contar las terapias");
  return (
    <Tile href="/admin/terapias" title="Terapias" icon={<TherapiesIcon />}>
      Visibles: {active.count ?? 0} · Ocultas: {hidden.count ?? 0}
    </Tile>
  );
}

export default function AdminHome() {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Administración</h1>
      <div className="mt-6 grid grid-cols-2 gap-4">
        <Suspense fallback={<TileFallback />}>
          <Summary />
        </Suspense>
        <Suspense fallback={<TileFallback />}>
          <ReportsSummary />
        </Suspense>
        <Suspense fallback={<TileFallback />}>
          <FollowUpSummary />
        </Suspense>
        <Suspense fallback={<TileFallback />}>
          <TherapiesSummary />
        </Suspense>
      </div>
    </main>
  );
}
