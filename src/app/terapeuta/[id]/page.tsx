// Public profile of a therapist. Everything the patient needs to know about the therapist, therapy by therapy. The phone and
// the mail are NOT in the page: they come only through the "Ver contacto" button (ADR-0003). The look lives in profile-view.tsx.
// Perfil público de un terapeuta. Todo lo que el paciente necesita saber, terapia por terapia. El teléfono y el mail NO
// están en la página: llegan solo con el botón "Ver contacto" (ADR-0003). El aspecto vive en profile-view.tsx.

import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { HealthNotice } from "@/components/health-notice";
import { SiteHeader } from "@/components/site-header";
import { loadPublicProfile } from "@/lib/profile-detail";
import { createAnonClient } from "@/lib/supabase/anon-client";
import { ProfileView } from "./profile-view";

export const metadata: Metadata = { title: "Perfil del terapeuta" };

type PageProps = { params: Promise<{ id: string }> };

async function ProfileContent({ params }: PageProps) {
  const { id } = await params;
  const profile = await loadPublicProfile(createAnonClient(), id);
  if (!profile) notFound();
  return <ProfileView profile={profile} />;
}

export default function ProfilePage({ params }: PageProps) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-3xl px-4 py-8">
        <p className="mb-4">
          <Link className="text-sm text-apagado underline hover:text-tinta" href="/buscar">← Volver a la búsqueda</Link>
        </p>
        <Suspense fallback={<p className="text-apagado">Cargando el perfil…</p>}>
          <ProfileContent params={params} />
        </Suspense>
        <HealthNotice className="mt-10" />
      </main>
    </>
  );
}
