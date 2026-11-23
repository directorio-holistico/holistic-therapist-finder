# ADR-0004: Country URL structure and search indexing
# ADR-0004: Estructura de URLs por país e indexación en buscadores

**Status / Estado:** Accepted (design). Implementation: planned, in small commits, not yet written.
**Date / Fecha:** 2026-11-23. **Decided by / Decidió:** the project owner / el dueño del proyecto.

---

## English

### Context
- Phase 1 countries are Argentina, Mexico and Spain. Chile is out of Phase 1 (decided 2026-11-23). Positioning starts with Argentina.
- Today the public routes are `/`, `/buscar`, `/terapeuta/[id]` and `/legal/*`. There is no `sitemap`, no `robots`, no Open Graph image and no canonical URL. Only `icon.png` exists as an SEO-related file. The home has one `h1` (the brand) and no `h2`.
- The whole interface is written in Argentine Spanish ("vos"). Mexico and Spain use "tú".
- `proxy.ts` runs only on `/ingresar`, `/mi-perfil`, `/auth` and `/admin`, so public pages stay cacheable. This must not change.

### Decision
1. **Country segment.** A `[country]` route segment with a fixed list: `ar`, `mx`, `es`. Any other value returns 404. Fixed routes (`/buscar`, `/legal`, `/terapeuta/...`) keep priority over the dynamic segment.
2. **Only `/ar` is indexed at first.** `/mx` and `/es` exist but carry `noindex` and stay out of the sitemap until the owner decides each country has enough approved profiles.
3. **Root `/`.** A temporary redirect (307) to `/ar`, declared in `next.config.ts` (not in `proxy.ts`). Later it can become a country selector without changing any other URL.
4. **What does not move.** `/terapeuta/[id]`, `/buscar` and `/legal/*` keep their addresses, so links already shared keep working. A profile belongs to one therapist and one country, so it needs no country variants.
5. **Search results.** `/buscar` gets `noindex, follow`, to avoid indexing endless filter combinations.
6. **`hreflang`.** Added only when two or more countries are published. It goes in the page metadata (`alternates.languages`) and in the sitemap.
7. **Language of the page.** `lang="es"` stays in the root layout for now. One variant per country is expressed in the copy and in `hreflang` (`es-AR`, `es-MX`, `es-ES`), not in several root layouts.
8. **Copy per country.** Home title, description and texts live in one dictionary per country. Argentina uses "vos"; Mexico and Spain use "tú". The rest of the interface stays in "vos" for now (known gap, hidden until those countries open).
9. **Structured data.** Only `Organization` with name and URL. No address, tax id or personal data of the site owner until the legal identification decision is made.
10. **Therapy pages** (`/ar/terapias/[terapia]`) are a later step. They need a readable identifier per therapy in the database, which is a migration with its own review. Pages without approved profiles get `noindex`.
11. **Site URL** is defined in one place (`src/lib/site.ts`) and used as `metadataBase`.

### Facts checked / Hechos verificados
- Next.js docs: `metadataBase`, `alternates.canonical`, `alternates.languages` (hreflang), `openGraph` and `robots` are supported in `metadata` / `generateMetadata`; a relative URL without `metadataBase` is a build error. [confirmed in Next.js docs, page updated 2026-11-18]
- Next.js docs: `sitemap.ts` accepts `alternates.languages` per entry; `robots` has its own file convention. [confirmed in Next.js docs, page updated 2026-08-18]
- Next.js docs: with Cache Components, `generateMetadata` that reads runtime data (`params`, `cookies`, `headers`, `searchParams`) or uncached data on an otherwise static page raises a build error and must be cached or marked as intentionally dynamic. [confirmed in Next.js docs]
- `redirects()` in `next.config.ts` for version 16.4.6: [to verify in the commit that uses it].

### Alternatives considered
- Everything under `/ar`: moves profiles and search, breaks shared links, needs many redirects. Rejected.
- `/` as the Argentine home and prefix only for other countries: no change now, but `/` would have to change later to become a selector. Rejected.
- One subdomain or domain per country: splits authority and adds cost and DNS work. Rejected for Phase 1. [INFERRED]
- Automatic redirect by IP or browser language: search engines may see only one version, and visitors cannot choose. Rejected. [INFERRED]

### Consequences and risks
- Medium: the root redirect adds one hop. It is temporary (307) so it can change later.
- Medium: an unknown first segment must return 404, not a blank page. Covered by a test and by the build.
- Medium: if `/` and `/ar` were both indexable they would duplicate content. The redirect prevents it.
- Low: Mexico and Spain copy in "tú" next to an interface in "vos". Hidden until those countries open.
- No new personal data, no database change, no permission change in this ADR. Therapy pages (item 10) will need their own review.
- Test plan: unit tests for the country list and the sitemap; `tsc --noEmit`, lint, tests and build; smoke test after deploy of `/`, `/ar`, `/mx`, `/sitemap.xml` and `/robots.txt`.

---

## Español

### Contexto
- Los países de la Fase 1 son Argentina, México y España. Chile queda fuera de la Fase 1 (decidido el 23/11/2026). El posicionamiento empieza por Argentina.
- Hoy las rutas públicas son `/`, `/buscar`, `/terapeuta/[id]` y `/legal/*`. No hay `sitemap`, ni `robots`, ni imagen de Open Graph (vista previa al compartir), ni URL canónica (URL preferida). Como archivo de SEO solo existe `icon.png`. La home tiene un `h1` (la marca) y ningún `h2`.
- Toda la interfaz está en español argentino ("vos"). México y España usan "tú".
- `proxy.ts` corre solo en `/ingresar`, `/mi-perfil`, `/auth` y `/admin`, así que las páginas públicas siguen cacheables. Esto no debe cambiar.

### Decisión
1. **Segmento de país.** Un segmento de ruta `[country]` con lista fija: `ar`, `mx`, `es`. Cualquier otro valor da 404. Las rutas fijas (`/buscar`, `/legal`, `/terapeuta/...`) tienen prioridad sobre el segmento dinámico.
2. **Al principio solo se indexa `/ar`.** `/mx` y `/es` existen pero llevan `noindex` (no indexar) y quedan fuera del sitemap hasta que el dueño decida que cada país tiene suficientes perfiles aprobados.
3. **Raíz `/`.** Redirección temporal (307) a `/ar`, declarada en `next.config.ts` (no en `proxy.ts`). Más adelante puede pasar a ser un selector de país sin cambiar ninguna otra URL.
4. **Lo que no se mueve.** `/terapeuta/[id]`, `/buscar` y `/legal/*` mantienen su dirección, así que los enlaces ya compartidos siguen funcionando. Un perfil pertenece a un terapeuta y a un país, por lo que no necesita variantes por país.
5. **Resultados de búsqueda.** `/buscar` lleva `noindex, follow` para no indexar combinaciones infinitas de filtros.
6. **`hreflang`.** Se agrega recién cuando haya dos o más países publicados, en los metadatos de la página (`alternates.languages`) y en el sitemap.
7. **Idioma de la página.** `lang="es"` queda en el layout raíz por ahora. La variante por país se expresa en los textos y en `hreflang` (`es-AR`, `es-MX`, `es-ES`), no con varios layouts raíz.
8. **Textos por país.** Título, descripción y textos de la home viven en un diccionario por país. Argentina usa "vos"; México y España usan "tú". El resto de la interfaz queda en "vos" por ahora (brecha conocida, oculta hasta que esos países abran).
9. **Datos estructurados.** Solo `Organization` con nombre y URL. Sin domicilio, identificación fiscal ni datos personales del titular hasta que se resuelva la decisión de identificación legal.
10. **Páginas por terapia** (`/ar/terapias/[terapia]`): paso posterior. Requieren un identificador legible por terapia en la base, que es una migración con su propia revisión. Las páginas sin perfiles aprobados llevan `noindex`.
11. **URL del sitio** definida en un solo lugar (`src/lib/site.ts`) y usada como `metadataBase`.

### Hechos verificados
- Documentación de Next.js: `metadataBase`, `alternates.canonical`, `alternates.languages` (hreflang), `openGraph` y `robots` se soportan en `metadata` / `generateMetadata`; una URL relativa sin `metadataBase` da error de build. [confirmado en la documentación de Next.js, página actualizada el 18/11/2026]
- Documentación de Next.js: `sitemap.ts` acepta `alternates.languages` por entrada; `robots` tiene su propio archivo. [confirmado en la documentación de Next.js, página actualizada el 18/08/2026]
- Documentación de Next.js: con Cache Components, un `generateMetadata` que lee datos de pedido (`params`, `cookies`, `headers`, `searchParams`) o datos sin cache en una página por lo demás estática da error de build y hay que cachearlo o marcarlo como dinámico a propósito. [confirmado en la documentación de Next.js]
- `redirects()` en `next.config.ts` para la versión 16.4.6: [a verificar en el commit que lo use].

### Alternativas consideradas
- Todo bajo `/ar`: mueve perfiles y búsqueda, rompe enlaces compartidos y exige muchas redirecciones. Descartada.
- `/` como home de Argentina y prefijo solo para los otros países: no cambia nada ahora, pero después habría que cambiar `/` para hacerlo selector. Descartada.
- Un subdominio o dominio por país: reparte la autoridad y suma costo y trabajo de DNS. Descartada para la Fase 1. [INFERIDO]
- Redirección automática por IP o idioma del navegador: los buscadores pueden ver una sola versión y el visitante no puede elegir. Descartada. [INFERIDO]

### Consecuencias y riesgos
- Medio: la redirección de la raíz suma un salto. Es temporal (307) para poder cambiarla.
- Medio: un primer segmento desconocido debe dar 404, no una página vacía. Lo cubre una prueba y el build.
- Medio: si `/` y `/ar` fueran ambas indexables duplicarían contenido. La redirección lo evita.
- Bajo: textos de México y España en "tú" junto a una interfaz en "vos". Quedan ocultos hasta que esos países abran.
- Sin datos personales nuevos, sin cambios en la base y sin cambios de permisos en este ADR. Las páginas por terapia (punto 10) necesitarán su propia revisión.
- Plan de pruebas: pruebas unitarias de la lista de países y del sitemap; `tsc --noEmit`, lint, tests y build; smoke test (prueba rápida) tras el deploy de `/`, `/ar`, `/mx`, `/sitemap.xml` y `/robots.txt`.
