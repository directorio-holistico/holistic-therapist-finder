// The email link lands HERE and only shows a button. The one-use token is spent when the person presses it (POST to
// /auth/verificar), so mail scanners and link previews that open the link cannot use it up.
// El enlace del mail aterriza ACÁ y solo muestra un botón. El token de un solo uso se gasta cuando la persona lo aprieta
// (POST a /auth/verificar), así los escáneres de mail y las vistas previas que abren el enlace no lo consumen.

import type { Metadata } from "next";
import { Suspense } from "react";
import { confirmSchema, safeNextPath } from "@/lib/auth/params";
import { ConfirmSubmit } from "./confirm-submit";

export const metadata: Metadata = { title: "Confirmar ingreso", robots: { index: false } };

type PageProps = { searchParams: Promise<Record<string, string | string[] | undefined>> };

async function ConfirmForm({ searchParams }: PageProps) {
  const raw = await searchParams;
  const first = (value: string | string[] | undefined) => (Array.isArray(value) ? value[0] : value);
  const parsed = confirmSchema.safeParse({ token_hash: first(raw.token_hash), type: first(raw.type), next: first(raw.next) });
  if (!parsed.success) {
    return (
      <p role="alert" className="mt-4 text-red-800 dark:text-red-300">
        El enlace está incompleto. <a className="underline" href="/ingresar">Pedí uno nuevo</a>.
      </p>
    );
  }
  return <ConfirmSubmit tokenHash={parsed.data.token_hash} type={parsed.data.type} next={safeNextPath(parsed.data.next)} />;
}

export default function ConfirmPage(props: PageProps) {
  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Confirmá tu ingreso</h1>
      <p className="mt-2 text-zinc-700 dark:text-zinc-300">Apretá el botón para entrar. Si no lo pediste vos, cerrá esta página.</p>
      <Suspense fallback={null}>
        <ConfirmForm {...props} />
      </Suspense>
    </main>
  );
}
