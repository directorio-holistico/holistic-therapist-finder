// Catalogs change rarely, so the search form reads them through a cache (refreshed about every hour). Called only
// after the request is known (inside Suspense), so a build never needs the database.
// Los catálogos cambian poco: el formulario los lee con caché (se renueva cada hora aproximadamente). Se llaman solo
// cuando ya se conoce el pedido (dentro de Suspense), así el build nunca necesita la base.

import { cacheLife } from "next/cache";
import { listLocations, listTherapies } from "@/lib/catalogs";
import { createAnonClient } from "@/lib/supabase/anon-client";

export async function getTherapies() {
  "use cache";
  cacheLife("hours");
  return listTherapies(createAnonClient());
}

export async function getLocationOptions(parentId: number | null) {
  "use cache";
  cacheLife("hours");
  return listLocations(createAnonClient(), parentId);
}
