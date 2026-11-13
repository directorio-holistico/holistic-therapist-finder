import type { Metadata } from "next";
import Link from "next/link";
import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: SITE_NAME, template: `%s | ${SITE_NAME}` },
  description: `${SITE_SLOGAN}. Encontrá terapeutas holísticos por terapia, país, ciudad y modo de atención.`,
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full flex flex-col">
        {children}
        <footer className="border-t px-4 py-4 text-center text-sm">
          <nav aria-label="Legales" className="flex flex-wrap justify-center gap-x-4 gap-y-1">
            <Link className="underline" href="/legal/terminos">Términos</Link>
            <Link className="underline" href="/legal/privacidad">Privacidad</Link>
            <Link className="underline" href="/legal">Legales</Link>
          </nav>
        </footer>
      </body>
    </html>
  );
}
