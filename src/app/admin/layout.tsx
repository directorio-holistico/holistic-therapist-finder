import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

export const metadata: Metadata = { title: "Administración", robots: { index: false, follow: false } };

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-3xl px-4 py-6">
      <nav aria-label="Administración" className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-zinc-300 pb-3 dark:border-zinc-700">
        <Link href="/admin" className="font-semibold text-zinc-900 dark:text-zinc-100">Administración</Link>
        <Link href="/admin/revisiones" className="underline">Revisiones</Link>
      </nav>
      {children}
    </div>
  );
}
