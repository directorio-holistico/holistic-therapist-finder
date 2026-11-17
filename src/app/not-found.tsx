import type { Metadata } from "next";
import Link from "next/link";
import { SiteHeader } from "@/components/site-header";

// The 404 page of the whole site, in Spanish and with the site's look. It also answers /admin for people who are not administrators
// (the panel says "not found" on purpose, so it does not reveal that it exists).
// La página 404 de todo el sitio, en español y con el aspecto del sitio. También responde /admin a quien no es administrador
// (el panel dice "no encontrada" a propósito, para no revelar que existe).

export const metadata: Metadata = { title: "Página no encontrada" };

export default function NotFound() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col items-center px-6 py-16 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-acento">Error 404</p>
        <h1 className="mt-3 font-display text-4xl font-semibold text-tinta sm:text-5xl">No encontramos esta página</h1>
        <p className="mt-4 text-lg text-apagado">
          Puede que el enlace esté mal escrito o que la página ya no exista.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
          <Link
            href="/buscar"
            className="inline-flex min-h-12 items-center rounded-full bg-boton px-7 text-base font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
          >
            Buscar terapeuta
          </Link>
          <Link href="/" className="inline-flex min-h-12 items-center px-2 font-medium text-tinta underline">
            Volver al inicio
          </Link>
        </div>
      </main>
    </>
  );
}
