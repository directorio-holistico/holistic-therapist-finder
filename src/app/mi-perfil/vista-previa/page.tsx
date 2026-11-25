// "Ver cómo queda": the therapist's own preview. READ ONLY: it shows what is SAVED (a draft, the changes in review, the last rejected
// proposal or the live profile) drawn by the same code as the public profile and the search card. Nobody else can see this page:
// it needs the login, reads with the person's own session and is never indexed.
// "Ver cómo queda": la vista previa del propio terapeuta. SOLO LECTURA: muestra lo GUARDADO (un borrador, los cambios en revisión, la
// última propuesta rechazada o el perfil vigente) dibujado por el mismo código que el perfil público y la tarjeta de la búsqueda.
// Nadie más puede ver esta página: pide ingresar, lee con la sesión de la propia persona y nunca se indexa.

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { ProfileCard } from "@/app/buscar/profile-card";
import { ProfileView } from "@/app/terapeuta/[id]/profile-view";
import { HealthNotice } from "@/components/health-notice";
import { requirePassword } from "@/lib/auth/password-gate";
import { getPublicEnv } from "@/lib/env";
import { photoPublicUrl } from "@/lib/photo";
import { isPendingPhotoPath } from "@/lib/photo-rules";
import { pendingPhotoUrl } from "@/lib/photo-storage";
import { buildPreview, type PreviewPhoto, type PreviewSource } from "@/lib/profile-preview";
import { loadProfilePreview } from "@/lib/profile-preview-load";
import { createServerSupabase } from "@/lib/supabase/server-client";

export const metadata: Metadata = { title: "Vista previa de mi perfil", robots: { index: false, follow: false } };

const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";
const TEXT_LINK = `text-acento underline underline-offset-4 ${FOCUS}`;
const PRIMARY = `inline-flex min-h-11 items-center rounded-full bg-boton px-5 font-medium text-boton-texto ${FOCUS}`;

// Says in words which saved version is on screen. / Dice con palabras qué versión guardada se ve.
function sourceText(source: PreviewSource, profileStatus: string): string {
  if (source === "draft") return "Estás viendo tu borrador guardado, que todavía no enviaste a revisión.";
  if (source === "in_review") return "Estás viendo los cambios que enviaste y que están en revisión.";
  if (source === "rejected") return "Estás viendo la propuesta que no se aprobó y que estás corrigiendo.";
  return profileStatus === "published" ? "Estás viendo tu perfil publicado." : "Estás viendo lo que cargaste, que todavía no está publicado.";
}

// The pending photo lives in a PRIVATE bucket: it is shown with a short-lived address, and only if it is in this profile's own folder.
// If it is gone, the live photo is shown (the editor does the same). undefined = use the path of the public bucket.
// La foto pendiente vive en un bucket PRIVADO: se muestra con una dirección de corta vida, y solo si está en la carpeta de este perfil.
// Si ya no está, se muestra la vigente (el editor hace lo mismo). undefined = usar la ruta del bucket público.
async function photoUrlFor(photo: PreviewPhoto, profileId: string, livePhotoPath: string | null): Promise<string | null | undefined> {
  if (photo.kind !== "pending") return undefined;
  let signed: string | null = null;
  try {
    signed = isPendingPhotoPath(photo.path, profileId) ? await pendingPhotoUrl(photo.path) : null;
  } catch {
    signed = null;
  }
  return signed ?? photoPublicUrl(getPublicEnv().supabaseUrl, livePhotoPath);
}

async function Preview() {
  // The session check reads the clock (token expiry): it must run on a real request, never in a prerender pass.
  // La verificación de sesión lee el reloj (vencimiento del token): debe correr en un pedido real, nunca en un prerender.
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);
  const data = await loadProfilePreview(supabase, auth.user.id);

  if (data.kind === "no-account") redirect("/mi-perfil/alta");
  if (data.kind === "blocked") return <p className="mt-4 text-apagado">Tu perfil no está disponible en este momento.</p>;

  const preview = buildPreview({
    profileId: data.profileId,
    defaults: data.defaults,
    catalogs: data.catalogs,
    tree: data.tree,
    countryIso: data.countryIso,
    isPinned: data.isPinned,
    shortNames: data.shortNames,
    livePhotoPath: data.livePhotoPath,
  });
  if (!preview) {
    return (
      <p className="mt-4 text-apagado">
        Todavía no hay nada para mostrar: falta tu nombre público. Completalo en <Link className={TEXT_LINK} href="/mi-perfil/editar">Editar perfil</Link>.
      </p>
    );
  }
  const photoUrl = await photoUrlFor(preview.photo, data.profileId, data.livePhotoPath);
  const view = { photoUrl };

  return (
    <>
      <p role="note" className="mt-4 rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-sm text-aviso-texto">
        <strong className="font-semibold">Vista previa: solo la ves vos.</strong> {sourceText(data.source, data.profileStatus)} Lo nuevo se publica cuando lo revisamos y lo aprobamos.
      </p>
      <p className="mt-4 flex flex-wrap gap-x-6 gap-y-2 text-sm">
        <Link className={TEXT_LINK} href="/mi-perfil">← Volver a mi perfil</Link>
        <Link className={TEXT_LINK} href="/mi-perfil/editar">Editar perfil</Link>
      </p>

      <section aria-labelledby="vp-card" className="mt-8">
        <h2 id="vp-card" className="font-display text-xl font-semibold text-tinta">Así se ve tu tarjeta en la búsqueda</h2>
        <div className="mx-auto mt-3 max-w-sm">
          <ProfileCard card={preview.card} preview={view} />
        </div>
      </section>

      <section aria-labelledby="vp-profile" className="mt-10">
        <h2 id="vp-profile" className="font-display text-xl font-semibold text-tinta">Así se ve tu perfil completo</h2>
        <div className="mt-3">
          <ProfileView profile={preview.detail} preview={view} />
        </div>
      </section>

      <p className="mt-8">
        <Link href="/mi-perfil/editar" className={PRIMARY}>Editar perfil</Link>
      </p>
    </>
  );
}

export default function ProfilePreviewPage() {
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10">
      <h1 className="font-display text-3xl font-semibold text-tinta">Vista previa de mi perfil</h1>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <Preview />
      </Suspense>
      <HealthNotice className="mt-10" />
    </main>
  );
}
