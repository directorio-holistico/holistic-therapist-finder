// One report: what was reported, who reported (optional mail), the profile and its state; then the decisions (close it, suspend or
// reinstate the profile). Everything written by the reporter is shown as plain text, never as markup.
// Una denuncia: qué se denunció, quién (mail opcional), el perfil y su estado; luego las decisiones (cerrarla, suspender o reponer
// el perfil). Todo lo que escribió quien denuncia se muestra como texto plano, nunca como marcado.

import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import {
  RESULT_NOTICES, canReinstate, canSuspend, parseReportId, profileStatusLabel, reasonLabel, reportStatusLabel,
} from "@/lib/admin/report-view";
import { emailHref } from "@/lib/contact-links";
import { formatDate } from "@/lib/format";
import { ReportForms } from "./report-forms";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ resultado?: string | string[] }>;
};

const Row = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="grid gap-0.5 sm:grid-cols-[12rem_1fr]">
    <dt className="font-medium text-zinc-900 dark:text-zinc-100">{label}</dt>
    <dd className="text-zinc-800 dark:text-zinc-200">{children}</dd>
  </div>
);

async function Detail({ params, searchParams }: Props) {
  const { supabase } = await requireAdmin();
  const id = parseReportId((await params).id);
  if (id === null) notFound();
  const result = (await searchParams).resultado;
  const notice = typeof result === "string" && (result === "suspendido" || result === "repuesto") ? RESULT_NOTICES[result] : undefined;

  const report = await supabase
    .from("reports")
    .select("id, profile_id, reason_id, details, reporter_email, status_id, created_at, resolved_at, resolution_note")
    .eq("id", id)
    .maybeSingle();
  if (report.error) throw new Error(`Could not read the report / No se pudo leer la denuncia: ${report.error.message}`);
  if (!report.data) notFound();
  const row = report.data;

  // No joins under RLS: each table on its own. / Sin joins bajo RLS: cada tabla por separado.
  const [reason, statuses, profile] = await Promise.all([
    supabase.from("report_reasons").select("code").eq("id", row.reason_id).maybeSingle(),
    supabase.from("report_statuses").select("id, code").limit(20),
    row.profile_id === null
      ? Promise.resolve({ data: null, error: null })
      : supabase.from("therapist_profiles").select("id, display_name, status_id, status_reason").eq("id", row.profile_id).maybeSingle(),
  ]);
  for (const read of [reason, statuses, profile]) if (read.error) throw new Error(`Could not read the report data / No se pudieron leer los datos: ${read.error.message}`);

  const statusCode = statuses.data?.find((status) => status.id === row.status_id)?.code ?? "?";
  const openId = statuses.data?.find((status) => status.code === "open")?.id;
  const isOpen = statusCode === "open";

  const profileStatus = profile.data
    ? await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle()
    : { data: null, error: null };
  if (profileStatus.error) throw new Error(`Could not read the profile status / No se pudo leer el estado del perfil: ${profileStatus.error.message}`);
  const profileCode = profileStatus.data?.code ?? null;

  const otherOpen = row.profile_id !== null && openId !== undefined
    ? await supabase.from("reports").select("id", { count: "exact", head: true }).eq("profile_id", row.profile_id).eq("status_id", openId).neq("id", row.id)
    : { count: null, error: null };
  if (otherOpen.error) throw new Error(`Could not count the reports / No se pudieron contar las denuncias: ${otherOpen.error.message}`);

  const mailLink = row.reporter_email ? emailHref(row.reporter_email) : null;

  return (
    <>
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">Denuncia n.º {row.id}</p>
      {notice && <p role="status" className="mt-4 rounded-md border border-green-600 bg-green-50 p-3 text-green-900">{notice}</p>}

      <dl className="mt-4 grid gap-3">
        <Row label="Motivo">{reasonLabel(reason.data?.code ?? "?")}</Row>
        <Row label="Estado">{reportStatusLabel(statusCode)}</Row>
        <Row label="Recibida el">{formatDate(row.created_at) ?? "—"}</Row>
        <Row label="Perfil">
          {profile.data ? (
            <>
              <span>{profile.data.display_name ?? "Sin nombre"}</span>
              {" · "}
              <span>{profileCode ? profileStatusLabel(profileCode) : "estado desconocido"}</span>
              {" · "}
              <Link href={`/terapeuta/${profile.data.id}`} className="underline">Ver perfil público</Link>
              {profileCode === "suspended" && profile.data.status_reason && (
                <span className="block text-sm">Motivo de la suspensión: {profile.data.status_reason}</span>
              )}
            </>
          ) : (
            "Perfil eliminado"
          )}
        </Row>
        <Row label="Detalle">
          {row.details ? <span className="block whitespace-pre-wrap break-words">{row.details}</span> : "Sin detalle"}
        </Row>
        <Row label="Mail de quien denunció">
          {row.reporter_email ? (mailLink ? <a href={mailLink} className="underline break-all">{row.reporter_email}</a> : <span className="break-all">{row.reporter_email}</span>) : "No dejó mail"}
        </Row>
        {otherOpen.count !== null && otherOpen.count > 0 && (
          <Row label="Otras abiertas">Hay {otherOpen.count} denuncia{otherOpen.count === 1 ? "" : "s"} abierta{otherOpen.count === 1 ? "" : "s"} más sobre este perfil.</Row>
        )}
        {!isOpen && (
          <Row label="Cierre">
            {formatDate(row.resolved_at) ?? "—"}
            {row.resolution_note && <span className="block whitespace-pre-wrap break-words">{row.resolution_note}</span>}
          </Row>
        )}
      </dl>

      <ReportForms
        reportId={row.id}
        isOpen={isOpen}
        profileId={profile.data?.id ?? null}
        canSuspend={profileCode !== null && canSuspend(profileCode)}
        canReinstate={profileCode !== null && canReinstate(profileCode)}
      />
    </>
  );
}

export default function ReportPage(props: Props) {
  return (
    <main>
      <h1 className="mt-6 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Denuncia</h1>
      <p className="mt-2"><Link href="/admin/denuncias" className="underline">← Volver a las denuncias</Link></p>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Detail {...props} />
      </Suspense>
    </main>
  );
}
