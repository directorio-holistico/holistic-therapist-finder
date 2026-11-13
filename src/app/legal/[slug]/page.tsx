import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LegalDocumentView } from "@/components/legal-document";
import { LEGAL_DOCUMENTS, findLegalDocument } from "@/lib/legal";

// Explicit props type: it does not depend on the route types that Next generates on build.
// Tipo de props explícito: no depende de los tipos de rutas que Next genera al compilar.
type LegalPageProps = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return LEGAL_DOCUMENTS.map((doc) => ({ slug: doc.slug }));
}

export async function generateMetadata({ params }: LegalPageProps): Promise<Metadata> {
  const { slug } = await params;
  const doc = findLegalDocument(slug);
  return { title: doc ? doc.title : "Legales" };
}

export default async function LegalPage({ params }: LegalPageProps) {
  const { slug } = await params;
  const doc = findLegalDocument(slug);
  if (!doc) notFound();
  return <LegalDocumentView doc={doc} />;
}
