import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LegalDocumentView } from "@/components/legal-document";
import { LEGAL_DOCUMENTS, findLegalDocument } from "@/lib/legal";

export function generateStaticParams() {
  return LEGAL_DOCUMENTS.map((doc) => ({ slug: doc.slug }));
}

export async function generateMetadata({ params }: PageProps<"/legal/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const doc = findLegalDocument(slug);
  return { title: doc ? doc.title : "Legales" };
}

export default async function LegalPage({ params }: PageProps<"/legal/[slug]">) {
  const { slug } = await params;
  const doc = findLegalDocument(slug);
  if (!doc) notFound();
  return <LegalDocumentView doc={doc} />;
}
