// Reports of profiles: the open ones first (the oldest on top), or the closed ones. Read with the administrator's session.
// Denuncias de perfiles: primero las abiertas (la más vieja arriba), o las cerradas. Se leen con la sesión del administrador.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import {
  RESULT_NOTICES, hasNextPage, pageRange, parseFilter, parsePage, reasonLabel, reportStatusLabel, type ReportFilter,
} from "@/lib/admin/report-view";
import { formatDate } from "@/lib/format";

type SearchParams = Promise<{ estado?: string | string[]; pagina?: string | string[]; resultado?: string | string[] }>;

const hrefFor = (filter: ReportFilter, page: number) => `/admin/denuncias?estado=${filter}${page > 1 ? `&pagina=${page}` : ""}`;

async function List({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireAdmin();
  const params = await searchParams;
  const filter = parseFilter(params.estado);
  const page = parsePage(params.pagina);
  const result = typeof params.resultado === "string" ? params.resultado : undefined;
  const notice = result === "cerrada" ? RESULT_NOTICES.cerrada : undefined;

  // No joins under RLS: each table on its own. / Sin joins bajo RLS: cada tabla por separado.
  const [statuses, reasons] = await Promise.all([
    supabase.from("report_statuses").select("id, code").limit(20),
    supabase.from("report_reasons").select("id, code").limit(50),
  ]);
  if (statuses.error || reasons.error) throw new Error("Could not read the report catalogs / No se pudieron leer los catálogos de denuncias");
  const openId = statuses.data.find((status) => status.code === "open")?.id;
  if (openId === undefined) throw new Error("The 'open' report status is missing / Falta el estado 'open' de denuncias");
  const statusCode = new Map(statuses.data.map((status) => [status.id, status.code]));
  const reasonCode = new Map(reasons.data.map((reason) => [reason.id, reason.code]));

  const { from, to } = pageRange(page);
  const base = supabase.from("reports").select("id, profile_id, reason_id, status_id, created_at, resolved_at", { count: "exact" });
  const rows = await (filter === "abiertas"
    ? base.eq("status_id", openId).order("created_at", { ascending: true })
    : base.neq("status_id", openId).order("resolved_at", { ascending: false })
  ).range(from, to);
  if (rows.error) throw new Error(`Could not read the reports / No se pudieron leer las denuncias: ${rows.error.message}`);

  const profileIds = [...new Set(rows.data.map((row) => row.profile_id).filter((id): id is string => id !== null))];
  const profiles = profileIds.length === 0
    ? { data: [], error: null }
    : await supabase.from("therapist_profiles").select("id, display_name").in("id", profileIds).limit(REPORT_PROFILE_LIMIT);
  if (profiles.error) throw new Error(`Could not read the profiles / No se pudieron leer los perfiles: ${profiles.error.message}`);
  const nameOf = new Map((profiles.data ?? []).map((profile) => [profile.id, profile.display_name]));
  const total = rows.count ?? rows.data.length;

  return (
    <>
      {notice && <p role="status" className="mt-4 rounded-lg border border-ok-borde bg-ok-fondo p-3 text-ok-texto">{notice}</p>}
      <nav aria-label="Filtro de denuncias" className="mt-4 flex gap-4">
        {(["abiertas", "cerradas"] as const).map((option) => (
          <Link key={option} href={hrefFor(option, 1)} aria-current={filter === option ? "page" : undefined}
            className={filter === option ? "inline-flex min-h-11 items-center font-semibold underline underline-offset-4 text-tinta" : "inline-flex min-h-11 items-center underline underline-offset-4 text-acento"}>
            {option === "abiertas" ? "Abiertas" : "Cerradas"}
          </Link>
        ))}
      </nav>

      {rows.data.length === 0 ? (
        <p className="mt-4 text-apagado">
          {filter === "abiertas" ? "No hay denuncias abiertas." : "No hay denuncias cerradas."}
        </p>
      ) : (
        <ul className="mt-4 grid gap-3">
          {rows.data.map((row) => (
            <li key={row.id} className="rounded-xl border border-linea bg-superficie p-5">
              <Link href={`/admin/denuncias/${row.id}`} className="font-display text-xl font-semibold text-tinta underline underline-offset-4">
                {reasonLabel(reasonCode.get(row.reason_id) ?? "?")}
              </Link>
              <p className="mt-1 text-tinta">
                {row.profile_id === null ? "Perfil eliminado" : (nameOf.get(row.profile_id) ?? "Perfil sin nombre")}
              </p>
              <p className="mt-1 text-sm text-apagado">
                Recibida el {formatDate(row.created_at) ?? "—"} · {reportStatusLabel(statusCode.get(row.status_id) ?? "?")}
                {row.resolved_at ? ` el ${formatDate(row.resolved_at) ?? "—"}` : ""}
              </p>
            </li>
          ))}
        </ul>
      )}

      {(page > 1 || hasNextPage(page, total)) && (
        <nav aria-label="Páginas" className="mt-4 flex items-center gap-4">
          {page > 1 && <Link href={hrefFor(filter, page - 1)} className="text-acento underline underline-offset-4">← Anteriores</Link>}
          <span className="text-sm text-apagado">Página {page}</span>
          {hasNextPage(page, total) && <Link href={hrefFor(filter, page + 1)} className="text-acento underline underline-offset-4">Siguientes →</Link>}
        </nav>
      )}
    </>
  );
}

// A page never has more than REPORTS_PAGE_SIZE reports, so this bound is never reached; it only keeps the query explicitly small.
// Una página nunca tiene más de REPORTS_PAGE_SIZE denuncias, así que este tope no se alcanza; solo deja la consulta explícitamente chica.
const REPORT_PROFILE_LIMIT = 100;

export default function ReportsPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Denuncias</h1>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <List searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
