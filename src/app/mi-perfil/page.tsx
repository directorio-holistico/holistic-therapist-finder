// "My profile", READ ONLY (step 1). The visitor must be logged in; the database (RLS) returns only their own rows.
// "Mi perfil", SOLO LECTURA (paso 1). Hay que estar ingresado; la base (RLS) devuelve solo las filas propias.

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { requirePassword } from "@/lib/auth/password-gate";
import { formatDate } from "@/lib/format";
import { loadPendingDocuments } from "@/lib/legal/pending";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { AcceptanceBanner } from "./acceptance-banner";
import { ApprovalNote } from "./approval-note";
import { DiscardDraftButton } from "./discard-draft-button";

export const metadata: Metadata = { title: "Mi perfil", robots: { index: false } };

const STATUS_LABELS: Record<string, string> = {
  unpublished: "Sin publicar",
  published: "Publicado",
  paused: "Pausado",
  suspended: "Suspendido",
  erased: "Eliminado",
};

// Colour never carries the meaning alone: the label is always written. Green = live, amber = waiting, red = a problem, grey = off (tokens in globals.css).
// El color nunca lleva solo el significado: la etiqueta siempre está escrita. Verde = en vivo, ámbar = en espera, rojo = problema, gris = apagado.
const BADGE = "inline-block rounded-full border px-3 py-0.5 text-sm font-semibold";
// Shared looks: card, primary button (like the header's round buttons), secondary button, text link.
// Looks compartidos: tarjeta, botón principal (como los botones redondos del encabezado), botón secundario, enlace de texto.
const CARD = "mt-6 rounded-xl border border-linea bg-superficie p-5";
const TITLE = "font-display text-xl font-semibold text-tinta";
const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";
const PRIMARY = `inline-flex min-h-11 items-center rounded-full bg-boton px-5 font-medium text-boton-texto ${FOCUS}`;
const SECONDARY = `inline-flex min-h-11 items-center rounded-full border border-tinta px-5 font-medium text-tinta hover:bg-fondo ${FOCUS}`;
const TEXT_LINK = `text-acento underline underline-offset-4 ${FOCUS}`;
const STATUS_STYLES: Record<string, string> = {
  unpublished: "border-aviso-borde bg-aviso-fondo text-aviso-texto",
  published: "border-ok-borde bg-ok-fondo text-ok-texto",
  paused: "border-neutro-borde bg-neutro-fondo text-neutro-texto",
  suspended: "border-peligro-borde bg-peligro-fondo text-peligro-texto",
  erased: "border-neutro-borde bg-neutro-fondo text-neutro-texto",
};

// Small decorative icons for the buttons (the text always goes with them). / Íconos chicos y decorativos para los botones (el texto siempre los acompaña).
const ICON = { xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", width: 18, height: 18, fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true, focusable: false };
const EyeIcon = () => (
  <svg {...ICON}>
    <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" />
    <circle cx="12" cy="12" r="3" />
  </svg>
);
const ArrowOutIcon = () => (
  <svg {...ICON}>
    <path d="M7 17 17 7M8 7h9v9" />
  </svg>
);

type Supabase = Awaited<ReturnType<typeof createServerSupabase>>;

// The state of the latest change the person made (draft, pending_review, approved, rejected...). It tells them where they are, and a
// draft that was never sent is seen by nobody. Reading it must never break this page, so any failure means "nothing to show".
// El estado del último cambio de la persona (borrador, en revisión, aprobado, rechazado...). Le dice dónde está, y un borrador que
// nunca se envió no lo ve nadie. Leerlo nunca debe romper esta página, así que cualquier falla significa "nada para mostrar".
async function latestRevisionCode(supabase: Supabase, profileId: string): Promise<string | null> {
  try {
    const { data: latest } = await supabase.from("profile_revisions").select("status_id").eq("profile_id", profileId).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!latest) return null;
    const { data: status } = await supabase.from("revision_statuses").select("code").eq("id", latest.status_id).maybeSingle();
    return status?.code ?? null;
  } catch {
    return null;
  }
}

// The message the administrator left on the latest approval that carried one (the person may have deleted it). Reading it must never
// break this page: any failure means "nothing to show".
// El mensaje que dejó el administrador en la última aprobación que traía uno (la persona pudo eliminarlo). Leerlo nunca debe
// romper esta página: cualquier falla significa "nada para mostrar".
async function latestApprovalNote(supabase: Supabase, profileId: string): Promise<{ id: string; text: string } | null> {
  try {
    const { data } = await supabase.from("profile_revisions").select("id, approval_note").eq("profile_id", profileId).not("approval_note", "is", null).order("decided_at", { ascending: false }).limit(1).maybeSingle();
    return data && data.approval_note ? { id: data.id, text: data.approval_note } : null;
  } catch {
    return null;
  }
}

async function Account({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  // The session check reads the clock (token expiry): it must run on a real request, never in a prerender pass.
  // La verificación de sesión lee el reloj (vencimiento del token): debe correr en un pedido real, nunca en un prerender.
  await connection();
  const supabase = await createServerSupabase();
  // getUser() validates the token with the auth server; getSession() alone would trust the cookie.
  // getUser() valida el token con el servidor de autenticación; getSession() solo confiaría en la cookie.
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  // An administrator can read every row of people and therapist_profiles: filter by the logged-in person.
  // Un administrador puede leer todas las filas de people y therapist_profiles: se filtra por la persona ingresada.
  const { data: person, error: personError } = await supabase.from("people").select("id, full_name").eq("auth_user_id", auth.user.id).maybeSingle();
  if (personError) throw new Error(`Could not read the account / No se pudo leer la cuenta: ${personError.message}`);

  // No joins under RLS: each table is read on its own. / Sin joins bajo RLS: cada tabla se lee por separado.
  const { data: profile, error: profileError } = person
    ? await supabase.from("therapist_profiles").select("id, status_id, display_name, headline, approved_at").eq("person_id", person.id).maybeSingle()
    : { data: null, error: null };
  if (profileError) throw new Error(`Could not read the profile / No se pudo leer el perfil: ${profileError.message}`);
  const { data: status } = profile
    ? await supabase.from("profile_statuses").select("code").eq("id", profile.status_id).maybeSingle()
    : { data: null };

  // An administrator without a therapist profile has nothing to "create": the panel is their place.
  // Quien administra y no tiene perfil de terapeuta no tiene nada que "crear": su lugar es el panel.
  const { data: isAdmin } = await supabase.rpc("is_admin");
  const adminOnly = isAdmin === true && (!person || !profile);

  // Documents with a new version to accept: only for someone who already has a profile (the database raises for a login without a person).
  // Administrators are never blocked, but they can still accept. / Documentos con versión nueva por aceptar: solo para quien ya tiene perfil.
  // Quien administra nunca se bloquea, pero igual puede aceptar.
  const pendingDocuments = person && profile ? await loadPendingDocuments(supabase) : [];
  const acceptanceFailed = (await searchParams).aceptacion === "error";
  const savedDraft = (await searchParams).guardado === "1";
  const revisionCode = person && profile ? await latestRevisionCode(supabase, profile.id) : null;
  const hasDraft = revisionCode === "draft";
  const approvalNote = person && profile ? await latestApprovalNote(supabase, profile.id) : null;

  return (
    <>
      <p className="mt-2 text-apagado">Ingresaste como <strong className="font-semibold text-tinta">{auth.user.email}</strong>.</p>
      {pendingDocuments === null ? (
        <p role="alert" className="mt-4 text-sm font-medium text-peligro-texto">No pudimos comprobar si hay documentos nuevos por aceptar. Recargá la página en unos minutos.</p>
      ) : pendingDocuments.length > 0 ? (
        <AcceptanceBanner pending={pendingDocuments} blocking={isAdmin !== true} failed={acceptanceFailed} />
      ) : null}
      {adminOnly ? (
        <section className={CARD}>
          <h2 className={TITLE}>Cuenta de administración</h2>
          <p className="mt-1 text-apagado">Esta cuenta administra el sitio. No tiene perfil de terapeuta.</p>
          <Link href="/admin" className={`mt-4 ${PRIMARY}`}>Ir a administración</Link>
        </section>
      ) : !person || !profile ? (
        <section className={CARD}>
          <h2 className={TITLE}>Tu alta todavía no está completa</h2>
          <p className="mt-1 text-apagado">Tu mail ya está verificado. Falta crear tu perfil de terapeuta.</p>
          <Link href="/mi-perfil/alta" className={`mt-4 ${PRIMARY}`}>Crear mi perfil</Link>
        </section>
      ) : (
        <>
          <section className={CARD}>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
              <h2 className={TITLE}>{profile.display_name ?? person.full_name}</h2>
              <span className={`${BADGE} ${STATUS_STYLES[status?.code ?? ""] ?? STATUS_STYLES.erased}`}>{STATUS_LABELS[status?.code ?? ""] ?? "—"}</span>
            </div>
            {profile.headline && <p className="mt-2 text-sm text-apagado">{profile.headline}</p>}
            {profile.approved_at && <p className="mt-1 text-sm text-apagado">Aprobado el {formatDate(profile.approved_at)}</p>}
            {revisionCode === "pending_review" && (
              <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-apagado">
                Cambios: <span className={`${BADGE} border-aviso-borde bg-aviso-fondo text-aviso-texto`}>En revisión</span> Te avisamos cuando estén revisados.
              </p>
            )}
            {savedDraft && hasDraft && <p role="status" className="mt-3 text-sm font-medium text-ok-texto">Guardamos tu borrador.</p>}
            {hasDraft && (
              <p role="note" className="mt-3 rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-sm text-aviso-texto">
                Tenés cambios guardados como borrador que todavía no se enviaron a revisión. Mientras no los envíes, nadie los ve.
              </p>
            )}
          </section>
          {/* The actions sit OUTSIDE the card: one main action, then the two ways of looking at the profile. / Las acciones van FUERA de la tarjeta: una principal y luego las dos formas de mirar el perfil. */}
          <div className="mt-4 grid grid-cols-2 gap-3">
            <Link href="/mi-perfil/editar" className={`${PRIMARY} col-span-2 justify-center`}>{hasDraft ? "Continuar y enviar" : "Editar perfil"}</Link>
            <Link href="/mi-perfil/vista-previa" className={`${SECONDARY} ${status?.code === "published" ? "" : "col-span-2 "}justify-center gap-2 px-3`}>
              <EyeIcon />
              Vista previa
            </Link>
            {status?.code === "published" && (
              <Link href={`/terapeuta/${profile.id}`} className={`${SECONDARY} justify-center gap-2 px-3`}>
                <ArrowOutIcon />
                Ver en el sitio
              </Link>
            )}
            {hasDraft && <div className="col-span-2"><DiscardDraftButton /></div>}
          </div>
        </>
      )}
      {!adminOnly && person && profile && approvalNote && <ApprovalNote revisionId={approvalNote.id} text={approvalNote.text} />}
      {!adminOnly && person && profile && (
        <section aria-labelledby="recordatorio" className="mt-8">
          <h2 id="recordatorio" className={TITLE}>Para tener presente</h2>
          <details className="mt-3 rounded-xl border border-linea bg-superficie p-4 text-tinta">
            <summary className={`cursor-pointer font-semibold ${FOCUS}`}>Cómo se ordena la lista</summary>
            <p className="mt-3">
              Cuando alguien busca, primero ve a quienes atienden en su ciudad o zona; después, a quienes atienden a distancia en su mismo país; y al
              final, a quienes atienden a distancia desde otros países. Dentro de cada grupo van primero los perfiles con foto, después los que tienen
              las tarifas al día y, por último, se ordena por antigüedad de aprobación. Para mejorar tu lugar, sumá tu foto y mantené tus tarifas al día.
            </p>
          </details>
          {/* Same look as the notice at the foot of every page: small, quiet, with the key phrase in bold. / Mismo aspecto que el aviso al pie de cada página: chico, discreto, con la frase clave en negrita. */}
          <aside aria-label="Avisos sobre dinero" className="mt-6 border-t border-linea pt-4 text-sm text-apagado">
            <p>
              <strong className="font-semibold text-tinta">El lugar en la lista no se compra.</strong> No cobramos por aparecer más arriba ni por destacar un perfil.
            </p>
            <p className="mt-1">
              <strong className="font-semibold text-tinta">Faro Holístico no te va a pedir dinero.</strong> Si alguien te escribe por WhatsApp o por mail, o te envía
              un enlace, y te pide plata en nuestro nombre, no somos nosotros. No pagues, no respondas y no compartas tu contraseña ni tus datos.
            </p>
          </aside>
        </section>
      )}
      {isAdmin === true && !adminOnly && <p className="mt-4 text-sm"><Link className={TEXT_LINK} href="/admin">Ir a administración</Link></p>}
      <p className="mt-6 text-sm"><Link className={TEXT_LINK} href="/mi-perfil/contrasena">Cambiar contraseña</Link></p>
    </>
  );
}

export default function MyProfilePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="font-display text-3xl font-semibold text-tinta">Mi perfil</h1>
      <Suspense fallback={<p className="mt-2 text-apagado">Cargando…</p>}>
        <Account searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
