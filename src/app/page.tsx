import Link from "next/link";
import { HeroStar } from "@/components/hero-star";
import { SacredGeometry } from "@/components/sacred-geometry";
import { SiteHeader } from "@/components/site-header";
import { BRAND_NAME } from "@/lib/brand";
import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";

export default function Home() {
  return (
    <>
      <SiteHeader />
      <main className="relative flex flex-1 flex-col items-center overflow-hidden px-6 pb-20 pt-6 text-center">
        <SacredGeometry className="pointer-events-none absolute left-1/2 top-0 w-[min(150vw,1100px)] -translate-x-1/2 text-oro opacity-25" />
        <div className="relative z-10 flex flex-col items-center">
          <HeroStar />
          <p className="mt-10 text-sm font-semibold uppercase tracking-[0.18em] text-acento">
            Directorio gratuito de terapias holísticas
          </p>
          <h1 className="mt-3 font-display text-6xl font-semibold leading-none tracking-tight text-tinta sm:text-7xl lg:text-8xl">
            {SITE_NAME}
          </h1>
          <p className="mt-3 text-base font-semibold uppercase tracking-[0.25em] text-apagado">By {BRAND_NAME}</p>
          <p className="mt-8 max-w-2xl font-display text-2xl font-medium leading-snug text-tinta sm:text-3xl">
            {SITE_SLOGAN}
          </p>
          <p className="mt-4 max-w-xl text-lg text-apagado">
            Elegí una terapia y una zona. Te mostramos terapeutas y su contacto. Sin cuenta y sin costo.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
            <Link
              href="/buscar"
              className="inline-flex min-h-12 items-center rounded-full bg-boton px-7 text-base font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
            >
              Buscar terapeuta
            </Link>
            <Link href="/ingresar" className="inline-flex min-h-12 items-center px-2 font-medium text-tinta underline">
              Soy terapeuta: ingresar
            </Link>
          </div>
          <p className="mt-10 text-sm text-apagado">Sitio en construcción.</p>
        </div>
      </main>
    </>
  );
}
