import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { signOut } from "@/app/mi-perfil/actions";

export const metadata: Metadata = { title: "Administración", robots: { index: false, follow: false } };

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-3xl px-4 py-6">
      <nav aria-label="Administración" className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-zinc-300 pb-3 dark:border-zinc-700">
        <Link href="/admin" className="font-semibold text-zinc-900 dark:text-zinc-100">Administración</Link>
        <Link href="/admin/revisiones" className="underline">Revisiones</Link>
        <Link href="/admin/denuncias" className="underline">Denuncias</Link>
        {/* a way out of the panel: an administrator account has no other page with a "Salir" button / una salida del panel: una cuenta de administración no tiene otra página con botón "Salir" */}
        <form action={signOut} className="ml-auto">
          <button type="submit" className="rounded-md border border-zinc-400 px-3 py-1 text-sm text-zinc-900 dark:text-zinc-100">Salir</button>
        </form>
      </nav>
      {children}
    </div>
  );
}
