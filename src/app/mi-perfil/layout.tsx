import type { ReactNode } from "react";
import { SiteHeader } from "@/components/site-header";

// The public header on the therapist pages, so there is always a way back to the home and the search.
// El encabezado público en las páginas del terapeuta, para que siempre haya un camino de vuelta al inicio y al buscador.
export default function MiPerfilLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <SiteHeader />
      {children}
    </>
  );
}
