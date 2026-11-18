import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { LegalDocumentView } from "@/components/legal-document";
import { PUBLIC_PAGES, findPublicDocument } from "@/lib/legal";

// Explicit props type: it does not depend on the route types that Next generates on build.
// Tipo de props explícito: no depende de los tipos de rutas que Next genera al compilar.
type LegalPageProps = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return PUBLIC_PAGES.map((doc) => ({ slug: doc.slug }));
}

export async function generateMetadata({ params }: LegalPageProps): Promise<Metadata> {
  const { slug } = await params;
  const doc = findPublicDocument(slug);
  return { title: doc ? doc.title : "Legales" };
}

// With Cache Components, reading params must happen inside <Suspense>. The documents are static: the shell is instant.
// Con Cache Components, leer params debe hacerse dentro de <Suspense>. Los documentos son estáticos: la cáscara es instantánea.
async function LegalContent({ params }: LegalPageProps) {
  const { slug } = await params;
  const doc = findPublicDocument(slug);
  if (!doc) notFound();
  return <LegalDocumentView doc={doc} />;
}

export default function LegalPage({ params }: LegalPageProps) {
  return (
    <Suspense fallback={<main className="mx-auto w-full max-w-3xl flex-1 px-4 py-8">Cargando…</main>}>
      <LegalContent params={params} />
    </Suspense>
  );
}
