// Notice shown to a therapist who has to accept new versions of the legal documents. One button accepts exactly what is listed.
// Aviso para el terapeuta que tiene que aceptar versiones nuevas de los documentos legales. Un botón acepta justo lo que se lista.

import Link from "next/link";
import { pendingDocumentLinks } from "@/lib/legal/acceptance";
import type { LegalDocumentCode } from "@/lib/legal/types";
import { acceptNewVersions } from "./actions";

type Props = {
  pending: readonly LegalDocumentCode[];
  // true when the therapist cannot edit until accepting (administrators are never blocked) / true si no puede editar hasta aceptar (quien administra nunca se bloquea)
  blocking: boolean;
  failed?: boolean;
};

export function AcceptanceBanner({ pending, blocking, failed = false }: Props) {
  const links = pendingDocumentLinks(pending);
  return (
    <section aria-labelledby="acceptance-title" className="mt-6 rounded-lg border border-amber-600 p-4 dark:border-amber-500">
      <h2 id="acceptance-title" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Actualizamos nuestros documentos</h2>
      <p className="mt-1 text-zinc-700 dark:text-zinc-300">
        Hay versiones nuevas de estos documentos. Leelos y, si estás de acuerdo, aceptalos:
      </p>
      <ul className="mt-2 list-disc pl-5 text-zinc-800 dark:text-zinc-200">
        {links.map((link) => (
          <li key={link.code}><Link className="underline" href={link.href}>{link.title}</Link></li>
        ))}
      </ul>
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
        {blocking
          ? "Hasta que los aceptes no podés cambiar tu perfil, tus tarifas ni tu foto. Tu perfil publicado sigue visible."
          : "Tu perfil publicado sigue visible."}{" "}
        Podés retirar tus consentimientos en cualquier momento.
      </p>
      {failed && (
        <p role="alert" className="mt-2 text-sm font-medium text-red-700 dark:text-red-400">
          No pudimos registrar tu aceptación. Probá de nuevo en unos minutos.
        </p>
      )}
      <form action={acceptNewVersions} className="mt-3">
        <button type="submit" className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white dark:bg-zinc-100 dark:text-zinc-900">
          Acepto las versiones nuevas
        </button>
      </form>
    </section>
  );
}
