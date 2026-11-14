// One revision: everything the administrator must check, then approve or reject. Nothing from the payload is trusted: see
// src/lib/admin/revision-view.ts. The phone and the e-mail are NOT shown here.
// Una revisión: todo lo que el administrador debe revisar, y aprobar o rechazar. Nada del payload es de confianza: ver
// src/lib/admin/revision-view.ts. El teléfono y el mail NO se muestran acá.

import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { loadViewLookups, locationPath } from "@/lib/admin/lookups";
import { describeRevision, decisionFacts, type LinkKind } from "@/lib/admin/revision-view";
import { requireAdmin } from "@/lib/admin/guard";
import { formatDate, formatMoney } from "@/lib/format";
import { DecisionForms } from "./decision-form";

type Props = { params: Promise<{ id: string }> };

const LINK_LABELS: Record<LinkKind, string> = { website: "Web", instagram: "Instagram", facebook: "Facebook", tiktok: "TikTok", youtube: "YouTube" };
const Row = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="grid gap-0.5 sm:grid-cols-[12rem_1fr]">
    <dt className="font-medium text-zinc-900 dark:text-zinc-100">{label}</dt>
    <dd className="text-zinc-800 dark:text-zinc-200">{children}</dd>
  </div>
);

async function Detail({ params }: Props) {
  const { supabase, userId } = await requireAdmin();
  const parsedId = z.uuid().safeParse((await params).id);
  if (!parsedId.success) notFound();

  const revision = await supabase
    .from("profile_revisions")
    .select("id, profile_id, status_id, payload, flagged_terms, is_priority, submitted_at, due_at, suggested_therapy")
    .eq("id", parsedId.data)
    .maybeSingle();
  if (revision.error) throw new Error(`Could not read the revision / No se pudo leer la revisión: ${revision.error.message}`);
  if (!revision.data) notFound();
  const row = revision.data;

  // No joins under RLS: each table on its own. / Sin joins bajo RLS: cada tabla por separado.
  const [status, profile, me, request, lookups] = await Promise.all([
    supabase.from("revision_statuses").select("code").eq("id", row.status_id).maybeSingle(),
    supabase.from("therapist_profiles").select("status_id, person_id").eq("id", row.profile_id).maybeSingle(),
    supabase.from("people").select("id").eq("auth_user_id", userId).maybeSingle(),
    supabase.from("location_requests").select("city_name, region_id").eq("profile_id", row.profile_id).is("resolved_at", null).maybeSingle(),
    loadViewLookups(supabase),
  ]);
  for (const result of [status, profile, me, request]) if (result.error) throw new Error(`Could not read the revision data / No se pudieron leer los datos: ${result.error.message}`);
  const profileStatus = profile.data
    ? await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle()
    : { data: null, error: null };

  const view = describeRevision(row.payload, lookups);
  const facts = decisionFacts(row.payload, lookups.contactTypes);
  const place = view?.locationId != null ? await locationPath(supabase, view.locationId) : null;
  const requestRegion = request.data ? await locationPath(supabase, request.data.region_id) : null;

  const isPending = status.data?.code === "pending_review";
  const isOwn = profile.data !== null && me.data !== null && profile.data.person_id === me.data.id;
  const whyNot = !isPending
    ? "Esta revisión ya no está pendiente."
    : isOwn
      ? "Es tu propio perfil: no podés aprobarlo (sí rechazarlo). Hace falta otra persona administradora."
      : !facts
        ? "El contenido no tiene el formato esperado: rechazala."
        : !facts.hasCity
          ? "Todavía no tiene ciudad: no se puede aprobar."
          : null;

  return (
    <>
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
        Enviada el {formatDate(row.submitted_at) ?? "—"} · responder antes del {formatDate(row.due_at) ?? "—"}
        {row.is_priority ? " · prioritaria" : ""}
        {profileStatus.data?.code === "unpublished" ? " · primera aprobación: el perfil se publica" : ""}
      </p>

      {row.flagged_terms.length > 0 && (
        <section role="note" className="mt-4 rounded-md border border-amber-500 bg-amber-50 p-3 text-amber-900">
          <h2 className="font-semibold">Palabras marcadas (posibles promesas de cura)</h2>
          <p>{row.flagged_terms.join(", ")}</p>
        </section>
      )}
      {request.data && (
        <section role="note" className="mt-4 rounded-md border border-amber-500 bg-amber-50 p-3 text-amber-900">
          <h2 className="font-semibold">Pidió una ciudad que no está en la lista</h2>
          <p>{request.data.city_name}{requestRegion ? ` (región: ${requestRegion})` : ""}</p>
        </section>
      )}

      {!view ? (
        <p className="mt-4 text-red-800">El contenido de esta revisión no tiene el formato esperado. Lo correcto es rechazarla.</p>
      ) : (
        <dl className="mt-4 grid gap-3">
          <Row label="Nombre público">{view.displayName ?? "—"}</Row>
          <Row label="Presentación">{view.headline ?? "—"}</Row>
          <Row label="Ciudad">{place ?? (view.locationId === null ? "Sin ciudad" : `#${view.locationId}`)}</Row>
          <Row label="Zona o barrio">{view.zone ?? "—"}</Row>
          <Row label="Empezó a atender">{view.practiceStartYear ?? "—"}</Row>
          <Row label="Idiomas">{view.languages.join(", ") || "—"}</Row>
          <Row label="Terapias">
            {view.therapies.length === 0 ? "—" : (
              <ul className="grid gap-1">
                {view.therapies.map((therapy, index) => (
                  <li key={index}>
                    <strong>{therapy.name}</strong>
                    {therapy.minutes !== null ? ` · ${therapy.minutes} min` : ""}
                    {` · ${therapy.serviceModes.join(", ") || "sin modalidad"} · ${therapy.sessionFormats.join(", ") || "sin formato"}`}
                    {therapy.rates.map((rate) => ` · ${rate.audience}: ${formatMoney(rate.amount, rate.currency)}`).join("")}
                  </li>
                ))}
              </ul>
            )}
          </Row>
          {row.suggested_therapy && <Row label="Terapia sugerida">{row.suggested_therapy}</Row>}
          <Row label="Contacto privado">
            {view.hasPhone ? `Teléfono cargado${view.phoneWhatsapp ? " (con WhatsApp)" : ""}` : "Sin teléfono"} · {view.hasEmail ? "mail cargado" : "sin mail"}
          </Row>
          <Row label="Enlaces públicos">
            {view.links.length === 0 ? "Ninguno" : (
              <ul className="grid gap-1">
                {view.links.map((link, index) => (
                  <li key={index}>
                    {LINK_LABELS[link.kind]}:{" "}
                    {link.href ? (
                      <a href={link.href} target="_blank" rel="noopener noreferrer nofollow" className="underline break-all">{link.href}</a>
                    ) : (
                      <span className="break-all text-red-800">{link.value} (formato inválido: no se abre)</span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Row>
        </dl>
      )}

      {isPending && <DecisionForms revisionId={row.id} canApprove={whyNot === null} whyNot={whyNot} linksToCheck={facts?.linksToCheck ?? 0} />}
    </>
  );
}

export default function RevisionPage(props: Props) {
  return (
    <main>
      <h1 className="mt-6 text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Revisión de perfil</h1>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Detail {...props} />
      </Suspense>
    </main>
  );
}
