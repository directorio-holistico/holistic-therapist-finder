import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { signOut } from "@/app/mi-perfil/actions";

export const metadata: Metadata = { title: "Administración", robots: { index: false, follow: false } };

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-3xl px-4 py-6">
      <nav aria-label="Administración" className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-linea pb-3">
        <Link href="/admin" className="inline-flex min-h-11 items-center font-display text-lg font-semibold text-tinta">Administración</Link>
        <Link href="/admin/revisiones" className="inline-flex min-h-11 items-center text-acento underline underline-offset-4">Revisiones</Link>
        <Link href="/admin/denuncias" className="inline-flex min-h-11 items-center text-acento underline underline-offset-4">Denuncias</Link>
        {/* a way out of the panel: an administrator account has no other page with a "Salir" button / una salida del panel: una cuenta de administración no tiene otra página con botón "Salir" */}
        <div className="ml-auto flex items-center gap-2">
          {/* a way back to the public site without logging out, next to "Salir" so both exits are together / un camino de vuelta al sitio público sin cerrar sesión, junto a "Salir" para que las dos salidas estén juntas */}
          <Link href="/" className="inline-flex min-h-11 items-center rounded-full border border-tinta px-4 text-sm font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">Volver al sitio</Link>
          <form action={signOut}>
            <button type="submit" className="inline-flex min-h-11 items-center rounded-full border border-tinta px-4 text-sm font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">Salir</button>
          </form>
        </div>
      </nav>
      {children}
    </div>
  );
}
