import Link from "next/link";
import { CONTROLLER_ADDRESS, CONTROLLER_NAME, getContactEmail } from "@/lib/legal/facts";
import { LEGAL_REVIEW_PENDING, LEGAL_UPDATED_LABEL, LEGAL_VERSIONS } from "@/lib/legal/versions";
import type { LegalDocument } from "@/lib/legal/types";

export function LegalReviewNotice() {
  if (!LEGAL_REVIEW_PENDING) return null;
  return (
    <p role="note" className="rounded-md border border-amber-400 bg-amber-50 p-3 text-sm text-amber-900">
      Texto provisorio, pendiente de revisión legal. Puede cambiar antes de la apertura al público.
    </p>
  );
}

export function LegalContact() {
  const email = getContactEmail();
  return (
    <section aria-labelledby="contacto-legal" className="mt-8 border-t pt-4 text-sm">
      <h2 id="contacto-legal" className="text-lg font-semibold">Responsable y contacto</h2>
      <p>Responsable: {CONTROLLER_NAME}.</p>
      <p>Domicilio: {CONTROLLER_ADDRESS ?? "a completar antes de la apertura al público"}.</p>
      <p>
        Contacto:{" "}
        {email ? <a className="underline" href={`mailto:${email}`}>{email}</a> : "a completar antes de la apertura al público"}.
      </p>
    </section>
  );
}

export function LegalDocumentView({ doc }: { doc: LegalDocument }) {
  return (
    <main className="mx-auto w-full max-w-3xl flex-1 space-y-4 px-4 py-8">
      <nav aria-label="Migas de pan" className="text-sm">
        <Link className="underline" href="/legal">Legales</Link>
      </nav>
      <h1 className="text-2xl font-bold">{doc.title}</h1>
      <p className="text-sm text-neutral-600">
        Versión {LEGAL_VERSIONS[doc.code]} · actualizado el {LEGAL_UPDATED_LABEL}
      </p>
      <LegalReviewNotice />
      {doc.sections.map((section) => (
        <section key={section.id} aria-labelledby={section.id} className="space-y-2">
          <h2 id={section.id} className="text-lg font-semibold">{section.title}</h2>
          {section.blocks.map((block, i) =>
            block.type === "p" ? (
              <p key={i}>{block.text}</p>
            ) : (
              <ul key={i} className="list-disc space-y-1 pl-6">
                {block.items.map((item) => <li key={item}>{item}</li>)}
              </ul>
            ),
          )}
        </section>
      ))}
      {doc.code === "privacy" || doc.code === "terms" ? <LegalContact /> : null}
    </main>
  );
}
