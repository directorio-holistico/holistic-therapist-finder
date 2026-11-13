import type { Metadata } from "next";
import Link from "next/link";
import { LegalReviewNotice } from "@/components/legal-document";
import { LEGAL_DOCUMENTS } from "@/lib/legal";

export const metadata: Metadata = { title: "Legales" };

export default function LegalIndex() {
  return (
    <main className="mx-auto w-full max-w-3xl flex-1 space-y-4 px-4 py-8">
      <h1 className="text-2xl font-bold">Legales</h1>
      <LegalReviewNotice />
      <ul className="space-y-3">
        {LEGAL_DOCUMENTS.map((doc) => (
          <li key={doc.code}>
            <Link className="font-semibold underline" href={`/legal/${doc.slug}`}>{doc.title}</Link>
            <p className="text-sm text-neutral-600">{doc.summary}</p>
          </li>
        ))}
      </ul>
    </main>
  );
}
