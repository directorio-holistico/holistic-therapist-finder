import type { Metadata } from "next";
import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: SITE_NAME, template: `%s | ${SITE_NAME}` },
  description: `${SITE_SLOGAN}. Encontrá terapeutas holísticos por terapia, país, ciudad y modo de atención.`,
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
