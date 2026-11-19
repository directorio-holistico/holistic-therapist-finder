// Profile editor (part A). Saves a draft revision; "Enviar a revisión" sends it to the administrator.
// Editor de perfil (parte A). Guarda una revisión borrador; "Enviar a revisión" la manda al administrador.

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { requirePassword } from "@/lib/auth/password-gate";
import { getPublicEnv } from "@/lib/env";
import { photoPublicUrl } from "@/lib/photo";
import { isPendingPhotoPath } from "@/lib/photo-rules";
import { pendingPhotoUrl } from "@/lib/photo-storage";
import { loadPendingDocuments } from "@/lib/legal/pending";
import { loadProfileEditor } from "@/lib/profile-load";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { AcceptanceBanner } from "../acceptance-banner";
import { ProfileForm } from "./profile-form";

export const metadata: Metadata = { title: "Editar mi perfil", robots: { index: false } };

async function Editor() {
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);
  const data = await loadProfileEditor(supabase, auth.user.id);

  if (data.kind === "no-account") redirect("/mi-perfil/alta");
  if (data.kind === "blocked") {
    return <p className="mt-4 text-zinc-700 dark:text-zinc-300">Tu perfil no admite cambios en este momento.</p>;
  }
  if (data.kind === "in-review") {
    return (
      <p className="mt-4 text-zinc-700 dark:text-zinc-300">
        Tu perfil está en revisión. No se puede cambiar hasta que lo revisemos. <Link className="underline" href="/mi-perfil">Volver</Link>
      </p>
    );
  }
  // New legal versions to accept: nothing can be edited until accepted (administrators are never blocked, like in the database).
  // The published profile stays published. If the check fails we do not guess: we show an error instead of the form.
  // Versiones legales nuevas por aceptar: no se puede editar nada hasta aceptar (quien administra nunca se bloquea, igual que en la base).
  // El perfil publicado sigue publicado. Si la comprobación falla no adivinamos: mostramos un error en vez del formulario.
  const pendingDocuments = await loadPendingDocuments(supabase);
  if (pendingDocuments === null) {
    return <p role="alert" className="mt-4 text-red-700 dark:text-red-400">No pudimos comprobar tu estado. Probá de nuevo en unos minutos.</p>;
  }
  if (pendingDocuments.length > 0) {
    const { data: isAdmin } = await supabase.rpc("is_admin");
    if (isAdmin !== true) return <AcceptanceBanner pending={pendingDocuments} blocking />;
  }
  // a pending photo is shown with a short-lived signed address; only if it belongs to this profile
  // la foto pendiente se muestra con una dirección firmada de corta vida; solo si es de este perfil
  const pendingUrl = data.defaults.photoNew && isPendingPhotoPath(data.defaults.photoNew, data.profileId) ? await pendingPhotoUrl(data.defaults.photoNew) : null;
  // a proposed photo whose file is gone (discarded by the therapist) is forgotten, so it is never sent again; a REJECTED proposal keeps its file / una foto propuesta cuyo archivo ya no está (descartada por el terapeuta) se olvida, para no volver a enviarla; una propuesta RECHAZADA conserva su archivo
  const defaults = data.defaults.photoNew && !pendingUrl ? { ...data.defaults, photoNew: "" } : data.defaults;
  return (
    <ProfileForm
      defaults={defaults}
      catalogs={data.catalogs}
      countries={data.tree.countries}
      regions={data.tree.regions}
      cities={data.tree.cities}
      initialCountryId={data.initialCountryId}
      initialRegionId={data.initialRegionId}
      missingCity={data.missingCity}
      lastRejection={data.lastRejection}
      livePhotoUrl={photoPublicUrl(getPublicEnv().supabaseUrl, data.livePhotoPath)}
      pendingPhotoUrl={pendingUrl}
    />
  );
}

export default function EditProfilePage() {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Editar mi perfil</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">
        Tus cambios se publican después de una revisión. También podés subir tu foto: la revisamos antes de publicarla.
      </p>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Editor />
      </Suspense>
    </main>
  );
}
