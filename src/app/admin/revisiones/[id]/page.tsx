// One revision: everything the administrator must check, then approve or reject. Nothing from the payload is trusted: see
// src/lib/admin/revision-view.ts. The phone IS shown (as text, administrator only) so the administrator can write to the person; the e-mail is NOT.
// Una revisión: todo lo que el administrador debe revisar, y aprobar o rechazar. Nada del payload es de confianza: ver
// src/lib/admin/revision-view.ts. El teléfono SÍ se muestra (como texto, solo al administrador) para poder escribirle a la persona; el mail NO.

import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { loadViewLookups, locationPath } from "@/lib/admin/lookups";
import { changedFields, contactPhone, describeRevision, decisionFacts, FIELD_NAMES, type FieldKey, type LinkKind } from "@/lib/admin/revision-view";
import { requireAdmin } from "@/lib/admin/guard";
import { pendingPhotoUrl } from "@/lib/photo-storage";
import { formatDate, formatMoney } from "@/lib/format";
import { DecisionForms } from "./decision-form";

type Props = { params: Promise<{ id: string }> };

const LINK_LABELS: Record<LinkKind, string> = { website: "Web", instagram: "Instagram", facebook: "Facebook", tiktok: "TikTok", youtube: "YouTube" };
// A changed row is marked with the word "Cambió" (not only a color) and, when it is a simple field, shows the previous value.
// Una fila que cambió se marca con la palabra "Cambió" (no solo con color) y, si es un campo simple, muestra el valor anterior.
const previousView = (payload: unknown, lookups: Parameters<typeof describeRevision>[1]) => (payload === undefined || payload === null ? null : describeRevision(payload, lookups));
const Row = ({ label, children, changed, before }: { label: string; children: React.ReactNode; changed?: boolean; before?: string | null }) => (
  <div className={`grid gap-0.5 sm:grid-cols-[12rem_1fr] ${changed ? "rounded-md border-l-4 border-green-600 bg-green-50 py-1 pl-2 dark:bg-green-950" : ""}`}>
    <dt className="font-medium text-zinc-900 dark:text-zinc-100">
      {label}
      {changed && <span className="ml-2 inline-block rounded bg-green-200 px-1.5 py-0.5 text-xs font-semibold text-green-950">Cambió</span>}
    </dt>
    <dd className="text-zinc-800 dark:text-zinc-200">
      {children}
      {changed && before !== undefined && <span className="block text-sm text-zinc-600 dark:text-zinc-400">Antes: {before ?? "—"}</span>}
    </dd>
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
  const [status, profile, me, request, lookups, selfSetting] = await Promise.all([
    supabase.from("revision_statuses").select("code").eq("id", row.status_id).maybeSingle(),
    supabase.from("therapist_profiles").select("status_id, person_id").eq("id", row.profile_id).maybeSingle(),
    supabase.from("people").select("id").eq("auth_user_id", userId).maybeSingle(),
    supabase.from("location_requests").select("city_name, region_id").eq("profile_id", row.profile_id).is("resolved_at", null).maybeSingle(),
    loadViewLookups(supabase),
    supabase.from("app_settings").select("value").eq("key", "moderation_allow_self_approval").maybeSingle(),
  ]);
  for (const result of [status, profile, me, request, selfSetting]) if (result.error) throw new Error(`Could not read the revision data / No se pudieron leer los datos: ${result.error.message}`);
  const profileStatus = profile.data
    ? await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle()
    : { data: null, error: null };

  // Last approved version of this profile = what the public sees today. Read with the administrator's own session (no new permission).
  // Última versión aprobada de este perfil = lo que el público ve hoy. Se lee con la sesión del admin (sin permisos nuevos).
  const approvedStatus = await supabase.from("revision_statuses").select("id").eq("code", "approved").maybeSingle();
  if (approvedStatus.error) throw new Error(`Could not read the statuses / No se pudieron leer los estados: ${approvedStatus.error.message}`);
  const previous = approvedStatus.data
    ? await supabase.from("profile_revisions").select("payload, decided_at").eq("profile_id", row.profile_id).eq("status_id", approvedStatus.data.id)
        .neq("id", row.id).order("decided_at", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (previous.error) throw new Error(`Could not read the previous version / No se pudo leer la versión anterior: ${previous.error.message}`);

  const view = describeRevision(row.payload, lookups);
  const changes = changedFields(row.payload, previous.data?.payload ?? null, lookups);
  const diff = changes?.kind === "diff" ? changes.changed : null;
  const was = previousView(previous.data?.payload, lookups);
  const mark = (key: FieldKey) => diff?.has(key) ?? false;
  const facts = decisionFacts(row.payload, lookups.contactTypes, row.profile_id);
  const phone = contactPhone(row.payload, lookups.contactTypes);
  // the proposed photo is shown only if its path is a pending file of THIS profile / la foto propuesta solo se muestra si es un archivo pendiente de ESTE perfil
  const photoUrl = view?.photo.kind === "set" && facts?.photoOk ? await pendingPhotoUrl(view.photo.path) : null;
  const previousPlace = diff?.has("location") && was?.locationId != null ? await locationPath(supabase, was.locationId) : null;
  const place = view?.locationId != null ? await locationPath(supabase, view.locationId) : null;
  const requestRegion = request.data ? await locationPath(supabase, request.data.region_id) : null;

  const isPending = status.data?.code === "pending_review";
  const isOwn = profile.data !== null && me.data !== null && profile.data.person_id === me.data.id;
  // The database decides (approve_revision re-checks the setting); the page only mirrors it so the button is not disabled for nothing.
  // La base decide (approve_revision vuelve a revisar el ajuste); la página solo lo refleja para no desactivar el botón en vano.
  const selfApprovalOn = selfSetting.data?.value === true;
  const whyNot = !isPending
    ? "Esta revisión ya no está pendiente."
    : isOwn && !selfApprovalOn
      ? "Es tu propio perfil: no podés aprobarlo (sí rechazarlo). Hace falta otra persona administradora."
      : !facts
        ? "El contenido no tiene el formato esperado: rechazala."
        : !facts.hasCity
          ? "Todavía no tiene ciudad: no se puede aprobar."
          : !facts.photoOk
            ? "La foto propuesta tiene una ruta inválida: rechazala."
            : null;

  return (
    <>
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
        Enviada el {formatDate(row.submitted_at) ?? "—"} · responder antes del {formatDate(row.due_at) ?? "—"}
        {row.is_priority ? " · prioritaria" : ""}
        {profileStatus.data?.code === "unpublished" ? " · primera aprobación: el perfil se publica" : ""}
      </p>

      {changes && (
        <section role="note" className="mt-4 rounded-md border border-green-600 bg-green-50 p-3 text-green-900">
          <h2 className="font-semibold">Qué cambió</h2>
          {changes.kind === "first" && <p>Primera versión de este perfil: todo es nuevo, revisá todo.</p>}
          {changes.kind === "unavailable" && <p>No se pudo comparar con la versión anterior: revisá todo.</p>}
          {changes.kind === "diff" && (
            changes.changed.size === 0
              ? <p>Sin cambios respecto de la última versión aprobada ({formatDate(previous.data?.decided_at ?? null) ?? "—"}).</p>
              : <p>{[...changes.changed].map((key) => FIELD_NAMES[key]).join(", ")}. <span className="text-sm">Comparado con la versión aprobada el {formatDate(previous.data?.decided_at ?? null) ?? "—"}. Lo que no figura acá no cambió.</span></p>
          )}
        </section>
      )}
      {isOwn && selfApprovalOn && (
        <section role="note" className="mt-4 rounded-md border border-amber-500 bg-amber-50 p-3 text-amber-900">
          <p>Autoaprobación activada (<code>moderation_allow_self_approval</code>): podés aprobar tu propio perfil. Es solo para pruebas; desactivala después.</p>
        </section>
      )}
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
          <Row label="Foto" changed={mark("photo")}>
            {view.photo.kind === "remove" ? "Pide quitar su foto actual." : view.photo.kind === "none" ? (changes?.kind === "first" ? "Sin foto cargada." : "Sin cambios en la foto.") : photoUrl ? (
              <span className="grid gap-1">
                {/* eslint-disable-next-line @next/next/no-img-element -- short-lived signed address of a private file / dirección firmada de corta vida de un archivo privado */}
                <img src={photoUrl} alt="Foto propuesta" className="size-40 rounded-full object-cover" />
                <span className="text-sm">Revisá que sea una foto personal (no logo, no de otra persona). Si no, rechazala con el motivo.</span>
              </span>
            ) : <span className="text-red-800">No se pudo mostrar la foto (archivo ausente o ruta inválida): rechazala.</span>}
          </Row>
          <Row label="Nombre público" changed={mark("displayName")} before={was?.displayName ?? null}>{view.displayName ?? "—"}</Row>
          <Row label="Presentación" changed={mark("headline")} before={was?.headline ?? null}>{view.headline ?? "—"}</Row>
          <Row label="Sobre mí" changed={mark("about")} before={was?.about ?? null}><span className="whitespace-pre-line">{view.about ?? "—"}</span></Row>
          <Row label="Ciudad" changed={mark("location")} before={previousPlace}>{place ?? (view.locationId === null ? "Sin ciudad" : `#${view.locationId}`)}</Row>
          <Row label="Zona o barrio" changed={mark("zone")} before={was?.zone ?? null}>{view.zone ?? "—"}</Row>
          <Row label="Empezó como terapeuta" changed={mark("practiceStartYear")} before={was?.practiceStartYear != null ? String(was.practiceStartYear) : null}>{view.practiceStartYear ?? "—"}</Row>
          <Row label="Idiomas" changed={mark("languages")} before={was ? was.languages.join(", ") || null : null}>{view.languages.join(", ") || "—"}</Row>
          <Row label="Terapias" changed={mark("therapies")}>
            {view.therapies.length === 0 ? "—" : (
              <ul className="grid gap-1">
                {view.therapies.map((therapy, index) => (
                  <li key={index}>
                    <strong>{therapy.name}</strong>
                    {therapy.description ? ` · «${therapy.description}»` : ""}
                    {therapy.minutes !== null ? ` · ${therapy.minutes} min` : ""}
                    {` · ${therapy.serviceModes.join(", ") || "sin modalidad"} · ${therapy.sessionFormats.join(", ") || "sin formato"}`}
                    {therapy.rates.map((rate) => ` · ${rate.audience}: ${formatMoney(rate.amount, rate.currency)}`).join("")}
                  </li>
                ))}
              </ul>
            )}
          </Row>
          {row.suggested_therapy && <Row label="Terapia sugerida">{row.suggested_therapy}</Row>}
          <Row label="Contacto privado" changed={mark("phone") || mark("email")}>
            {phone ? `Teléfono: ${phone.text}${phone.whatsapp ? " (con WhatsApp)" : ""}` : "Sin teléfono"} · {view.hasEmail ? "mail cargado" : "sin mail"}
          </Row>
          <Row label="Enlaces públicos" changed={mark("links")}>
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
