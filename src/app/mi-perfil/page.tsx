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
import { signOut } from "./actions";
import { DiscardDraftButton } from "./discard-draft-button";

export const metadata: Metadata = { title: "Mi perfil", robots: { index: false } };

const STATUS_LABELS: Record<string, string> = {
  unpublished: "Sin publicar",
  published: "Publicado",
  paused: "Pausado",
  suspended: "Suspendido",
  erased: "Eliminado",
};

// Colour never carries the meaning alone: the label is always written. Green = live, amber = waiting, red = a problem, grey = off.
// El color nunca lleva solo el significado: la etiqueta siempre está escrita. Verde = en vivo, ámbar = en espera, rojo = problema, gris = apagado.
const BADGE = "inline-block rounded-full border px-2 py-0.5 font-semibold";
const STATUS_STYLES: Record<string, string> = {
  unpublished: "border-amber-500 bg-amber-50 text-amber-900",
  published: "border-green-600 bg-green-50 text-green-900",
  paused: "border-zinc-400 bg-zinc-100 text-zinc-800",
  suspended: "border-red-600 bg-red-50 text-red-900",
  erased: "border-zinc-400 bg-zinc-100 text-zinc-800",
};

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

  return (
    <>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">Ingresaste como <strong>{auth.user.email}</strong>.</p>
      {pendingDocuments === null ? (
        <p role="alert" className="mt-4 text-sm font-medium text-red-700 dark:text-red-400">No pudimos comprobar si hay documentos nuevos por aceptar. Recargá la página en unos minutos.</p>
      ) : pendingDocuments.length > 0 ? (
        <AcceptanceBanner pending={pendingDocuments} blocking={isAdmin !== true} failed={acceptanceFailed} />
      ) : null}
      {adminOnly ? (
        <section className="mt-6 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
          <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Cuenta de administración</h2>
          <p className="mt-1 text-zinc-700 dark:text-zinc-300">Esta cuenta administra el sitio. No tiene perfil de terapeuta.</p>
          <Link href="/admin" className="mt-3 inline-block rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">Ir a administración</Link>
        </section>
      ) : !person || !profile ? (
        <section className="mt-6 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
          <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Tu alta todavía no está completa</h2>
          <p className="mt-1 text-zinc-700 dark:text-zinc-300">Tu mail ya está verificado. Falta crear tu perfil de terapeuta.</p>
          <Link href="/mi-perfil/alta" className="mt-3 inline-block rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">Crear mi perfil</Link>
        </section>
      ) : (
        <section className="mt-6 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
          <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">{profile.display_name ?? person.full_name}</h2>
          {profile.headline && <p className="mt-1 text-zinc-800 dark:text-zinc-200">{profile.headline}</p>}
          <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
            Estado: <span className={`${BADGE} ${STATUS_STYLES[status?.code ?? ""] ?? STATUS_STYLES.erased}`}>{STATUS_LABELS[status?.code ?? ""] ?? "—"}</span>
            {profile.approved_at ? ` · aprobado el ${formatDate(profile.approved_at)}` : ""}
          </p>
          {revisionCode === "pending_review" && (
            <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
              Cambios: <span className={`${BADGE} border-amber-500 bg-amber-50 text-amber-900`}>En revisión</span> Te avisamos cuando estén revisados.
            </p>
          )}
          {savedDraft && hasDraft && <p role="status" className="mt-3 text-sm font-medium text-green-800 dark:text-green-400">Guardamos tu borrador.</p>}
          {hasDraft && (
            <p role="note" className="mt-3 rounded-md border border-amber-400 bg-amber-50 p-3 text-sm text-amber-900">
              Tenés cambios guardados como borrador que todavía no se enviaron a revisión. Mientras no los envíes, nadie los ve.
            </p>
          )}
          <div className="mt-3 flex flex-wrap items-start gap-3">
            <Link href="/mi-perfil/editar" className="inline-block rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">{hasDraft ? "Continuar y enviar" : "Editar mi perfil"}</Link>
            {hasDraft && <DiscardDraftButton />}
          </div>
        </section>
      )}
      {isAdmin === true && !adminOnly && <p className="mt-4 text-sm"><Link className="underline" href="/admin">Ir a administración</Link></p>}
      <p className="mt-6 text-sm"><Link className="underline" href="/mi-perfil/contrasena">Cambiar mi contraseña</Link></p>
      <form action={signOut} className="mt-4">
        <button type="submit" className="rounded-md border border-zinc-400 px-4 py-2 text-zinc-900 dark:text-zinc-100">Salir</button>
      </form>
    </>
  );
}

export default function MyProfilePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Mi perfil</h1>
      <Suspense fallback={<p className="mt-2 text-zinc-600">Cargando…</p>}>
        <Account searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
