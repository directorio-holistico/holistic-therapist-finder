// Catalogs change rarely, so the search form reads them through a cache (refreshed about every hour). Called only
// after the request is known (inside Suspense), so a build never needs the database.
// Los catálogos cambian poco: el formulario los lee con caché (se renueva cada hora aproximadamente). Se llaman solo
// cuando ya se conoce el pedido (dentro de Suspense), así el build nunca necesita la base.

import { cacheLife, cacheTag } from "next/cache";
import { listLocations, listTherapies } from "@/lib/catalogs";
import { createAnonClient } from "@/lib/supabase/anon-client";

// Tag of the therapy list: the admin screen that adds, hides or shows a therapy expires it, so the change shows right away.
// Etiqueta de la lista de terapias: la pantalla de admin que agrega, oculta o muestra una terapia la vence, así el cambio se ve enseguida.
export const THERAPIES_CACHE_TAG = "catalog-therapies";

export async function getTherapies() {
  "use cache";
  cacheLife("hours");
  cacheTag(THERAPIES_CACHE_TAG);
  return listTherapies(createAnonClient());
}

export async function getLocationOptions(parentId: number | null) {
  "use cache";
  cacheLife("hours");
  return listLocations(createAnonClient(), parentId);
}
