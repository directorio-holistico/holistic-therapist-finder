# Glossary / Glosario

One word per concept, everywhere: code, database, UI copy and documentation. If a term is not here, add it **before** using it.
Una palabra por concepto, en todos lados: código, base de datos, textos de la interfaz y documentación. Si un término no está acá, se agrega **antes** de usarlo.

Code and database identifiers are in English (`snake_case` in SQL, `camelCase` in TypeScript). The interface starts in Spanish.
Los identificadores de código y base de datos van en inglés. La interfaz arranca en español.

| Identifier (EN) | Término (ES) | Meaning / Significado | Do not use / No usar |
|---|---|---|---|
| `therapy` | terapia | A holistic discipline offered by a therapist (catalog entry). Disciplina holística que ofrece un terapeuta (entrada del catálogo). | tratamiento, treatment, disciplina, servicio |
| `therapist` | terapeuta | A person who registers and publishes a profile. Persona que se registra y publica un perfil. | profesional, practitioner, proveedor |
| `visitor` | visitante / paciente | Anyone who searches. No account, no personal data stored. Quien busca. Sin cuenta y sin datos personales guardados. | usuario (ambiguous), cliente |
| `profile` | perfil | The public page of a therapist. Its live version is the approved one. Página pública del terapeuta. Su versión vigente es la aprobada. | ficha pública, listing |
| `person` | persona | One record per human being; roles are attached to it. Un registro por ser humano; los roles se le asignan. | usuario, account |
| `revision` | revisión | A proposed change to a profile, waiting for admin approval. Cambio propuesto a un perfil, a la espera de aprobación del administrador. | edición pendiente, draft change |
| `location` | ubicación | A node of the hierarchy country > region > city. Nodo de la jerarquía país > región > ciudad. | zona (reserved for the optional neighborhood text), lugar |
| `mode` | modo | How a therapy is delivered: in person or remote. Cómo se brinda: presencial o a distancia. | modalidad, tipo de atención |
| `format` | formato | Individual or group sessions (or both). Sesiones individuales o grupales (o ambas). | tipo de sesión |
| `rate` | tarifa | Optional approximate price per session, per therapy and per audience. Precio orientativo opcional por sesión, por terapia y por audiencia. | precio, honorarios |
| `audience` | audiencia | Who a rate applies to: people from the therapist's country, or other countries. A quién aplica una tarifa: personas del país del terapeuta u otros países. | público |
| `contact` | contacto | Phone, email and website of a therapist. Teléfono, mail y web del terapeuta. | datos de contacto (as a table name) |
| `contact reveal` | revelado de contacto | The moment a visitor asks to see a therapist's phone/email. Se registra sin datos del visitante. El momento en que un visitante pide ver teléfono/mail. | vista, click |
| `unmet search` | búsqueda sin resultado | A search with no results; stored as uncovered demand. Búsqueda sin resultados; se guarda como demanda no cubierta. | búsqueda fallida |
| `moderation` | moderación | Admin review of profiles and revisions, with a recorded reason. Revisión del administrador sobre perfiles y revisiones, con motivo registrado. | aprobación manual |
| `status` | estado | Lifecycle state of a profile or revision (catalog tables). Estado del ciclo de vida de un perfil o revisión (tablas de catálogo). | situación |
| `paused` | pausado | Profile hidden by the therapist; nothing is deleted. Perfil oculto por el terapeuta; no se borra nada. | inactivo |
| `suspended` | suspendido | Profile hidden by an admin, with a reason. Perfil oculto por el administrador, con motivo. | bloqueado |
| `erased` | eliminado | Profile removed at the therapist's request; personal data deleted. Perfil dado de baja a pedido del terapeuta; datos personales borrados. | borrado lógico (use only for non-personal records) |
| `fingerprint` | huella | Irreversible keyed hash (HMAC) kept for one year after an erasure to detect repeated sign-ups. Hash irreversible con clave, guardado un año tras una eliminación para detectar altas repetidas. | copia, backup |
| `admin` | administrador | Role that moderates. Rol que modera. | superusuario |

Rules / Reglas:
1. Never mix two words for one concept (for example, `therapy_id` in one table and `treatment_id` in another).
2. Catalogs (therapies, statuses, languages, contact types...) are tables with an `id`, never enums or fixed `CHECK` lists.
3. Dates are `timestamptz` in UTC.
