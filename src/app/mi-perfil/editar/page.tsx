// Profile editor (part A). Saves a draft revision; "Enviar a revisión" sends it to the administrator.
// Editor de perfil (parte A). Guarda una revisión borrador; "Enviar a revisión" la manda al administrador.

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { loadProfileEditor } from "@/lib/profile-load";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { ProfileForm } from "./profile-form";

export const metadata: Metadata = { title: "Editar mi perfil", robots: { index: false } };

async function Editor() {
  await connection();
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
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
  return (
    <ProfileForm
      defaults={data.defaults}
      catalogs={data.catalogs}
      countries={data.tree.countries}
      regions={data.tree.regions}
      cities={data.tree.cities}
      initialCountryId={data.initialCountryId}
      initialRegionId={data.initialRegionId}
      missingCity={data.missingCity}
      lastRejection={data.lastRejection}
    />
  );
}

export default function EditProfilePage() {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Editar mi perfil</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">
        Tus cambios se publican después de una revisión. La foto se agrega en un paso posterior.
      </p>
      <Suspense fallback={<p className="mt-4 text-zinc-600">Cargando…</p>}>
        <Editor />
      </Suspense>
    </main>
  );
}
