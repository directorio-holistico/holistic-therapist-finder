import type { Metadata } from "next";
import Image from "next/image";
import localFont from "next/font/local";
import Link from "next/link";
import { ThemeToggle } from "@/components/theme-toggle";
import { BRAND_NAME } from "@/lib/brand";
import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";
import { THEME_INIT_SCRIPT } from "@/lib/theme";
import "./globals.css";

const fraunces = localFont({
  src: "./fonts/fraunces-latin-wght-normal.woff2",
  variable: "--font-fraunces",
  weight: "100 900",
  display: "swap",
});

const dmSans = localFont({
  src: "./fonts/dm-sans-latin-wght-normal.woff2",
  variable: "--font-dm-sans",
  weight: "100 1000",
  display: "swap",
});

export const metadata: Metadata = {
  title: { default: SITE_NAME, template: `%s | ${SITE_NAME}` },
  description: `${SITE_SLOGAN}. Encontrá terapeutas holísticos por terapia, país, ciudad y modo de atención.`,
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" data-theme="claro" suppressHydrationWarning className={`${fraunces.variable} ${dmSans.variable} h-full antialiased`}>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      </head>
      <body className="min-h-full flex flex-col">
        {children}
        <footer className="border-t border-linea px-4 py-6 text-center text-sm">
          <div className="flex flex-col items-center gap-4">
            <div className="flex items-center gap-3 text-apagado">
              <Image src="/brand/logo-claro.webp" alt={BRAND_NAME} width={72} height={77} className="h-[77px] w-[72px] dark:hidden" />
              <Image src="/brand/logo-oscuro.webp" alt={BRAND_NAME} width={72} height={77} className="hidden h-[77px] w-[72px] dark:block" />
              <span>Un proyecto de {BRAND_NAME}</span>
            </div>
            <nav aria-label="Legales" className="flex flex-wrap justify-center gap-x-4 gap-y-1">
              <Link className="underline" href="/legal/terminos">Términos</Link>
              <Link className="underline" href="/legal/privacidad">Privacidad</Link>
              <Link className="underline" href="/legal">Legales</Link>
            </nav>
            <ThemeToggle />
          </div>
        </footer>
      </body>
    </html>
  );
}
