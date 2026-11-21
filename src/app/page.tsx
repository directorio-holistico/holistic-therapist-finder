import Link from "next/link";
import { HealthNotice } from "@/components/health-notice";
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
          <p className="mt-6 text-base font-medium text-acento sm:mt-10">
            Directorio gratuito de terapias holísticas
          </p>
          <h1 className="mt-2 font-display text-5xl font-semibold leading-none tracking-tight text-tinta sm:text-7xl lg:text-8xl">
            {SITE_NAME}
          </h1>
          <p className="mt-2 text-base text-apagado">Un proyecto de {BRAND_NAME}</p>
          <p className="mt-5 max-w-2xl font-display text-2xl font-medium leading-snug text-tinta sm:mt-8 sm:text-3xl">
            {SITE_SLOGAN}
          </p>
          <p className="mt-4 max-w-xl text-lg text-apagado max-sm:order-1">
            Elegí una terapia y una zona. Te mostramos terapeutas y su contacto. Sin cuenta y sin costo.
          </p>
          <div className="mt-6 flex flex-wrap items-center justify-center gap-4 sm:mt-8">
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
          <HealthNotice className="mt-12 max-w-2xl max-sm:order-2" />
        </div>
      </main>
    </>
  );
}
