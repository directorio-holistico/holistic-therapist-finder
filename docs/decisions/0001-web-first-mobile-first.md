# ADR-0001: Web-first, mobile-first platform / Plataforma web, mobile-first

## English

**Status:** Accepted (platform). Hosting details are pending a deployment test (see ADR-0002, to be written).
**Date:** 2026-11-10

### Context
The product is a free directory. Patients search by therapy and location without creating an account, usually arriving from a search engine or a link shared in a chat. Therapists register, publish a profile, and manage it from a phone or a computer. There is one developer.

### Decision
Build a **web application, designed mobile-first**, using Next.js (App Router) with strict TypeScript. No native app in Phase 1.

### Why
- Patients should not have to install anything for a one-off search.
- A directory depends on being found: public pages must be indexable, which a native app cannot offer. Pages for each therapy and city are planned for a later phase.
- One codebase instead of separate Android and iOS ones.
- App stores add review, developer-account, privacy and content-policy overhead; the web deploys freely.
- Anyone reviewing the project can open a link and use the demo.

### What "mobile-first" means here
- Layouts are designed for small screens first and enhanced for larger ones.
- Accessibility target: WCAG 2.1 AA.
- Public pages use static generation or incremental regeneration so they load fast. A performance budget will be defined later.
- Touch interaction is tested on a real device using preview deployments.

### Alternatives considered
- Native app (Android/iOS): rejected for Phase 1. Higher cost, no search-engine discovery, store review.
- Cross-platform framework: rejected for Phase 1. Still needs store publishing; adds a second stack.
- Installable web app (PWA): not now. Reconsidered in Phase 2 or 3 as an enhancement, for example quick access to the therapist panel.

### Consequences
- No push notifications and no presence in app stores in Phase 1.
- Strong fit with search-engine discovery and with the planned SEO pages.
- Revisit native only if a need appears that the web cannot cover, such as push notifications or precise geolocation.

---

## Español

**Estado:** Aceptada (plataforma). Los detalles de hosting quedan pendientes de una prueba de despliegue (ADR-0002, a escribir).
**Fecha:** 2026-11-10

### Contexto
El producto es un directorio gratuito. El paciente busca por terapia y ubicación sin crear cuenta, y suele llegar desde un buscador o un link compartido por chat. El terapeuta se registra, publica su perfil y lo gestiona desde el celular o la computadora. Hay una sola persona desarrollando.

### Decisión
Construir una **aplicación web, diseñada primero para celular**, con Next.js (App Router) y TypeScript estricto. Sin app nativa en la Fase 1.

### Por qué
- El paciente no debería instalar nada para una búsqueda puntual.
- Un directorio vive de ser encontrado: las páginas públicas deben poder indexarse, y una app nativa no lo permite. Las páginas por terapia y ciudad están previstas para una fase posterior.
- Un solo código, en lugar de uno para Android y otro para iOS.
- Las tiendas de apps suman revisión, cuenta de desarrollador, privacidad y políticas de contenido; la web se despliega libremente.
- Quien revise el proyecto puede abrir un link y usar el demo.

### Qué significa "mobile-first" acá
- Los diseños se piensan primero para pantallas chicas y se amplían para las grandes.
- Objetivo de accesibilidad: WCAG 2.1 AA.
- Las páginas públicas usan generación estática o regeneración incremental para cargar rápido. El presupuesto de rendimiento se define más adelante.
- La interacción táctil se prueba en un dispositivo real con los despliegues de vista previa (Preview).

### Alternativas consideradas
- App nativa (Android/iOS): descartada para la Fase 1. Más costo, sin descubrimiento por buscadores, revisión de las tiendas.
- Framework multiplataforma: descartado para la Fase 1. Igual hay que publicar en tiendas y suma un segundo stack.
- Web instalable (PWA): no ahora. Se reconsidera en la Fase 2 o 3 como mejora, por ejemplo acceso rápido al panel del terapeuta.

### Consecuencias
- Sin notificaciones push ni presencia en tiendas en la Fase 1.
- Muy buen encaje con el descubrimiento por buscadores y con las páginas de SEO previstas.
- Se vuelve a evaluar lo nativo solo si aparece una necesidad que la web no cubre, como notificaciones push o geolocalización fina.
