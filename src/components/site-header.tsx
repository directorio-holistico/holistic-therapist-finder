import Image from "next/image";
import Link from "next/link";
import { SITE_NAME } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="relative z-10 flex items-center justify-between gap-4 px-4 py-4 sm:px-8">
      <Link href="/" className="flex min-h-11 items-center gap-2 rounded-md sm:gap-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">
        <Image src="/brand/estrella-claro.webp" alt="" width={40} height={40} className="size-10 dark:hidden" />
        <Image src="/brand/estrella-oscuro.webp" alt="" width={40} height={40} className="hidden size-10 dark:block" />
        <span className="whitespace-nowrap font-display text-lg sm:text-xl font-semibold text-tinta">{SITE_NAME}</span>
      </Link>
      <nav aria-label="Principal" className="flex items-center gap-2 sm:gap-4">
        <Link href="/buscar" className="hidden min-h-11 items-center rounded-md px-3 font-medium text-tinta hover:underline sm:inline-flex focus-visible:outline-2 focus-visible:outline-acento">
          Buscar
        </Link>
        <Link
          href="/ingresar"
          className="inline-flex min-h-11 items-center whitespace-nowrap rounded-full border border-tinta px-4 font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
        >
          Soy terapeuta
        </Link>
      </nav>
    </header>
  );
}
