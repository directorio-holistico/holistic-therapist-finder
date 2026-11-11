# ADR-0003: Rate limiting and bot protection for contact reveal
# ADR-0003: Límite de pedidos y protección contra bots en el revelado de contacto

**Status / Estado:** Accepted (design). Implementation: planned DB migration + web server route, not yet written.
**Date / Fecha:** 2026-11-11. **Decided by / Decidió:** the project owner / el dueño del proyecto.

---

## English

### Context
Phone and email of a therapist leave the database only through `reveal_contact` (commit 21). That function is executable by the `anon` role, and the `anon` key is public by design (it ships in the browser). So anyone can call it directly against the database API, profile by profile, and harvest every phone. A limit placed only in the website server can be bypassed by calling the database directly. Also, the database cannot see the visitor's address when the website server makes the call.

### Decision
1. **Close the direct door.** `reveal_contact` stops being executable by `anon`. The only caller is the website server (role `service_role`, secret key in server environment variables, never in the browser or the repo).
2. **One server route** (`POST /api/reveal`) does, in order: (a) read the visitor's address from the platform header; (b) verify a **Cloudflare Turnstile** token (widget mode "managed": invisible, shows a check only when it doubts); (c) call one database function that counts and reveals **in a single transaction**.
3. **Counting in the database** (shared by all server instances): table `rate_limit_hits` (origin hash, UTC day, counter). The origin hash is **HMAC-SHA256 with a secret key** over the address (IPv4 full; IPv6 cut to its /64 prefix). The raw address is never stored.
4. **Limit: 20 reveals per origin per UTC day** (decided by the owner), stored as a private setting so it can change without a deploy. Over the limit, the function raises a dedicated error and reveals nothing.
5. **Retention:** `rate_limit_hits` rows older than 2 days are purged (service role job). The HMAC key can be rotated at any time; the only effect is that today's counters restart.
6. **Platform layer:** one Vercel WAF rate-limiting rule on the Hobby plan (the plan allows one rate-limit rule among 3 custom rules) as a coarse burst brake on `/api/*`. It is an extra layer, not the business rule.
7. **If Turnstile is unreachable:** fail closed for reveal (the patient sees "try again in a few minutes"); search is unaffected.
8. `search_profiles` and `log_search` stay callable by `anon`: their data is public by design and the counters are bounded (finite combinations, capped count).

### Facts checked / Hechos verificados
- Vercel documents `x-forwarded-for` as the public IP of the client and says it overwrites that header when behind a proxy to prevent spoofing; a trusted proxy option exists only on Enterprise. [confirmed in Vercel docs]
- Turnstile has a free plan with up to 20 widgets and all widget types. Sources disagree on whether the free plan has a monthly request cap (1 million vs none); at this project's volume it does not matter. Cloudflare publishes no SLA for the free plan according to one third-party review. [partly confirmed]
- Vercel WAF rate limiting is available on all plans; Hobby has one rate-limit rule within 3 custom rules. [confirmed in Vercel docs]

### Alternatives considered
- Limit only in Next.js: bypassable by calling the database directly. Rejected.
- Redis service (Upstash or similar) for counters: one more vendor and secret; the database already shares state across instances. Rejected for Phase 1.
- Supabase Edge Function as the gate: also sees the address, but adds a second runtime and deploy pipeline. Rejected.
- Captcha on every reveal: more friction than needed. Rejected (owner accepts a captcha that only sometimes shows).
- Vercel WAF alone: cannot express a configurable daily business rule and is not shared with other hosts. Kept only as a coarse layer.

### Consequences and risks
- Medium: many patients behind one address (university, mobile carrier network sharing addresses) can hit 20 before the day ends. Mitigation: configurable limit; watch real blocks after launch.
- Medium: an attacker with a pool of addresses can still harvest slowly. The measures raise the cost; they do not make it impossible. Mitigation: Turnstile, daily counters per profile that the admin can inspect for spikes, therapists publish their phone voluntarily.
- The day window is a fixed UTC day: up to 2x the limit can pass around midnight. Accepted.
- Personal data: an address is personal data (Ley 25.326, GDPR). Only a keyed hash is stored for 2 days; the address goes to Cloudflare for verification, which must be named in the privacy policy. To confirm with legal review.
- Test plan: SQL tests (limit reached, per-origin isolation, error code, purge, no access for `anon`/`authenticated`); unit tests for address normalization and HMAC; the existing test 14 is adapted because the caller changes from `anon` to `service_role`.

---

## Español

### Contexto
El teléfono y el mail del terapeuta salen de la base solo por `reveal_contact` (commit 21). Esa función la puede ejecutar el rol `anon`, y la clave `anon` es pública por diseño (viaja en el navegador). Entonces cualquiera puede llamarla directo contra la API de la base, perfil por perfil, y juntar todos los teléfonos. Un límite puesto solo en el servidor de la web se saltea llamando a la base directamente. Además, la base no ve la dirección del visitante cuando llama el servidor de la web.

### Decisión
1. **Cerrar la puerta directa.** `reveal_contact` deja de ser ejecutable por `anon`. El único que la llama es el servidor de la web (rol `service_role`, clave secreta en variables de entorno del servidor, nunca en el navegador ni en el repo).
2. **Una ruta de servidor** (`POST /api/reveal`) hace, en orden: (a) lee la dirección del visitante del encabezado de la plataforma; (b) verifica un token de **Cloudflare Turnstile** (modo "managed": invisible, muestra una comprobación solo cuando duda); (c) llama a una función de la base que cuenta y revela **en una sola transacción**.
3. **El conteo en la base** (compartido por todas las instancias): tabla `rate_limit_hits` (hash del origen, día UTC, contador). El hash es **HMAC-SHA256 con clave secreta** sobre la dirección (IPv4 completa; IPv6 recortada a su prefijo /64). La dirección real nunca se guarda.
4. **Límite: 20 revelados por origen por día UTC** (decidido por el dueño), guardado como ajuste privado para cambiarlo sin desplegar. Pasado el límite, la función lanza un error propio y no revela nada.
5. **Retención:** las filas de `rate_limit_hits` de más de 2 días se purgan (tarea con service role). La clave HMAC se puede rotar cuando sea; el único efecto es que los contadores de hoy arrancan de cero.
6. **Capa de plataforma:** una regla de límite de pedidos del WAF de Vercel en el plan Hobby (permite una regla de límite entre 3 reglas propias), como freno grueso de ráfagas sobre `/api/*`. Es una capa extra, no la regla de negocio.
7. **Si Turnstile no responde:** se bloquea el revelado (el paciente ve "probá de nuevo en unos minutos"); la búsqueda no se afecta.
8. `search_profiles` y `log_search` siguen ejecutables por `anon`: sus datos son públicos por diseño y los contadores tienen cota (combinaciones finitas, cuenta con tope).

### Hechos verificados
- Vercel documenta `x-forwarded-for` como la IP pública del cliente y dice que sobrescribe ese encabezado detrás de un proxy para evitar falsificación; el proxy de confianza existe solo en Enterprise. [confirmado en la documentación de Vercel]
- Turnstile tiene plan gratis con hasta 20 widgets y todos los tipos de widget. Las fuentes no coinciden en si el plan gratis tiene tope mensual (1 millón vs ninguno); con el volumen de este proyecto no importa. Según una reseña de terceros, Cloudflare no publica SLA para el plan gratis. [parcialmente confirmado]
- El límite de pedidos del WAF de Vercel está en todos los planes; Hobby tiene una regla de límite entre 3 reglas propias. [confirmado en la documentación de Vercel]

### Alternativas consideradas
- Límite solo en Next.js: se saltea llamando directo a la base. Descartada.
- Servicio Redis (Upstash o similar) para los contadores: otro proveedor y otro secreto; la base ya comparte estado entre instancias. Descartada para la Fase 1.
- Edge Function de Supabase como puerta: también ve la dirección, pero suma otro entorno de ejecución y otro despliegue. Descartada.
- Captcha en cada revelado: más fricción de la necesaria. Descartada (el dueño acepta un captcha que solo a veces aparece).
- Solo el WAF de Vercel: no expresa una regla diaria configurable de negocio y no es portable a otro hosting. Queda solo como capa gruesa.

### Consecuencias y riesgos
- Medio: muchos pacientes detrás de una misma dirección (universidad, redes móviles que comparten direcciones) pueden llegar a 20 antes de fin de día. Mitigación: límite configurable; mirar los bloqueos reales tras el lanzamiento.
- Medio: un atacante con un conjunto de direcciones puede juntar teléfonos de a poco. Las medidas suben el costo, no lo hacen imposible. Mitigación: Turnstile, contadores diarios por perfil que el admin puede revisar buscando picos, y los terapeutas publican su teléfono voluntariamente.
- La ventana es un día UTC fijo: cerca de la medianoche pueden pasar hasta 2 veces el límite. Aceptado.
- Datos personales: una dirección IP es dato personal (Ley 25.326, GDPR). Se guarda solo un hash con clave durante 2 días; la dirección va a Cloudflare para la verificación, y eso debe nombrarse en la política de privacidad. A confirmar con revisión legal.
- Plan de pruebas: pruebas SQL (límite alcanzado, aislamiento entre orígenes, código de error, purga, sin acceso para `anon`/`authenticated`); pruebas unitarias de normalización de dirección y HMAC; la prueba 14 existente se adapta porque quien llama pasa de `anon` a `service_role`.
