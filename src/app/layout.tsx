import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Directorio de terapeutas holísticos",
  description:
    "Encontrá terapeutas holísticos por terapia, país, ciudad y modo de atención.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
