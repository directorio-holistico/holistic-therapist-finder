import Link from "next/link";
import { CONTROLLER_ADDRESS, CONTROLLER_NAME, getContactEmail } from "@/lib/legal/facts";
import { INFO_VERSIONS, LEGAL_REVIEW_PENDING, LEGAL_UPDATED_LABEL, LEGAL_VERSIONS } from "@/lib/legal/versions";
import type { InfoDocument, LegalDocument } from "@/lib/legal/types";

export function LegalReviewNotice() {
  if (!LEGAL_REVIEW_PENDING) return null;
  return (
    <p role="note" className="rounded-xl border border-aviso-borde bg-aviso-fondo p-4 text-sm text-aviso-texto">
      Texto provisorio, pendiente de revisión legal. Puede cambiar antes de la apertura al público.
    </p>
  );
}

export function LegalContact() {
  const email = getContactEmail();
  return (
    <section aria-labelledby="contacto-legal" className="mt-8 border-t border-linea pt-4 text-sm">
      <h2 id="contacto-legal" className="font-display text-xl font-semibold text-tinta">Responsable y contacto</h2>
      <p>Responsable: {CONTROLLER_NAME}.</p>
      <p>Domicilio: {CONTROLLER_ADDRESS ?? "a completar antes de la apertura al público"}.</p>
      <p>
        Contacto:{" "}
        {email ? <a className="text-acento underline underline-offset-4" href={`mailto:${email}`}>{email}</a> : "a completar antes de la apertura al público"}.
      </p>
    </section>
  );
}

export function LegalDocumentView({ doc }: { doc: LegalDocument | InfoDocument }) {
  const version = doc.code === "legal_notice" || doc.code === "cookies" ? INFO_VERSIONS[doc.code] : LEGAL_VERSIONS[doc.code];
  return (
    <main className="mx-auto w-full max-w-3xl flex-1 space-y-4 px-4 py-8">
      <nav aria-label="Migas de pan" className="text-sm">
        <Link className="text-acento underline underline-offset-4" href="/legal">Legales</Link>
      </nav>
      <h1 className="font-display text-3xl font-semibold text-tinta">{doc.title}</h1>
      <p className="text-sm text-apagado">
        Versión {version} · actualizado el {LEGAL_UPDATED_LABEL}
      </p>
      <LegalReviewNotice />
      {doc.sections.map((section) => (
        <section key={section.id} aria-labelledby={section.id} className="space-y-2">
          <h2 id={section.id} className="font-display text-xl font-semibold text-tinta">{section.title}</h2>
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
      {doc.code === "privacy" || doc.code === "terms" || doc.code === "legal_notice" ? <LegalContact /> : null}
    </main>
  );
}
