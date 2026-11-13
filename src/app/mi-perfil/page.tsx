// "My profile", READ ONLY (step 1). The visitor must be logged in; the database (RLS) returns only their own rows.
// "Mi perfil", SOLO LECTURA (paso 1). Hay que estar ingresado; la base (RLS) devuelve solo las filas propias.

import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { formatDate } from "@/lib/format";
import { createServerSupabase } from "@/lib/supabase/server-client";
import { signOut } from "./actions";

export const metadata: Metadata = { title: "Mi perfil", robots: { index: false } };

const STATUS_LABELS: Record<string, string> = {
  unpublished: "Sin publicar",
  published: "Publicado",
  paused: "Pausado",
  suspended: "Suspendido",
  erased: "Eliminado",
};

async function Account() {
  // The session check reads the clock (token expiry): it must run on a real request, never in a prerender pass.
  // La verificación de sesión lee el reloj (vencimiento del token): debe correr en un pedido real, nunca en un prerender.
  await connection();
  const supabase = await createServerSupabase();
  // getUser() validates the token with the auth server; getSession() alone would trust the cookie.
  // getUser() valida el token con el servidor de autenticación; getSession() solo confiaría en la cookie.
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");

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

  return (
    <>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">Ingresaste como <strong>{auth.user.email}</strong>.</p>
      {!person || !profile ? (
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
            Estado: <strong>{STATUS_LABELS[status?.code ?? ""] ?? "—"}</strong>
            {profile.approved_at ? ` · aprobado el ${formatDate(profile.approved_at)}` : ""}
          </p>
          <Link href="/mi-perfil/editar" className="mt-3 inline-block rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">Editar mi perfil</Link>
        </section>
      )}
      <form action={signOut} className="mt-6">
        <button type="submit" className="rounded-md border border-zinc-400 px-4 py-2 text-zinc-900 dark:text-zinc-100">Salir</button>
      </form>
    </>
  );
}

export default function MyProfilePage() {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Mi perfil</h1>
      <Suspense fallback={<p className="mt-2 text-zinc-600">Cargando…</p>}>
        <Account />
      </Suspense>
    </main>
  );
}
