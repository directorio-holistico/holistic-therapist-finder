import type { ReactNode } from "react";
import { SiteHeader } from "@/components/site-header";

// The public header on the login page, so there is always a way back to the home and the search.
// El encabezado público en la página de ingreso, para que siempre haya un camino de vuelta al inicio y al buscador.
export default function IngresarLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <SiteHeader />
      {children}
    </>
  );
}
