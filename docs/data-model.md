# Phase 1 data model / Modelo de datos de la Fase 1

Status: proposed, approved for design on 2026-11-11. No SQL yet; migrations come later and are tested first on a local Postgres with real roles.
Estado: propuesto, aprobado a nivel diseño el 2026-11-11. Todavía sin SQL; las migraciones vienen después y se prueban primero en un Postgres local con roles reales.

Terms follow [glossary.md](glossary.md). Catalogs are tables with an `id`, never enums or fixed `CHECK` lists. Dates are `timestamptz` (UTC).

## 1. Scope

**In Phase 1:** therapy catalog; search by therapy + location (+ mode); public profile; contact reveal; unmet searches; therapist sign-up and panel; admin panel (moderation); legal pages.

**Out of Phase 1:** verification and featured profiles, response-time badge, statistics, subscriptions, multi-language UI (translation tables exist, only Spanish is filled), search by need, SEO pages per therapy and city, patient accounts, reviews and ratings, appointments, payments, chat, analytics, currency conversion.

No table is created "just in case".

## 2. Tables (34)

### 2.1 Catalogs (14)
`therapies`, `therapy_translations`, `languages`, `currencies` (ARS, CLP, MXN, EUR, USD), `contact_types`, `service_modes` (in person, remote), `session_formats` (individual, group), `rate_audiences` (own country, other countries), `profile_statuses` (unpublished, published, paused, suspended, erased), `revision_statuses` (draft, pending_review, approved, rejected, discarded), `roles` (therapist, admin), `location_levels` (country, region, city), `locations`, `location_translations`.
`locations` is a tree through `parent_id`. A country stores its `iso_code` and `default_currency_id`.

### 2.2 Core (12)
| Table | Key content |
|---|---|
| `people` | One record per human. Full name, login email, `auth_user_id`, `erased_at`. Anonymized on erasure. |
| `person_roles` | `person_id` + `role_id`. |
| `therapist_profiles` | Live (public) version: `person_id` (unique), `status_id`, base `location_id` (city), optional neighborhood text, short presentation, `practice_start_year`, photo path, approval dates, pause/suspension reason. |
| `profile_therapies` | Therapies of a profile (maximum 4, configurable) + approximate `session_minutes` per therapy. |
| `profile_therapy_rates` | Optional rate per therapy and audience: amount + `currency_id`. Unique per therapy and audience; amount ≥ 0; amount and currency both present or both absent; one currency per audience inside a profile (trigger). |
| `profile_languages` | Languages of service. |
| `profile_service_modes` | In person / remote (one or both). |
| `profile_session_formats` | Individual / group (one or both). |
| `profile_contacts` | `contact_type_id` + value (text). Phone is mandatory; email and website are optional. Phone rows have `accepts_whatsapp`. |
| `profile_revisions` | Proposed changes: JSON `payload`, status, `last_changed_at`, `due_at`, high-priority flag, suggested therapy (short text), decision (who, when, reason). Only one open revision per profile (partial unique index). |
| `moderation_events` | Who approved, rejected or suspended, when and why. |
| `terms_acceptances` | Person, document, version, accepted date and `revoked_at`. Holds the legal declaration, the terms and the optional marketing consent. |

### 2.3 Demand, reports and operations (8)
`unmet_searches` (therapy, location, mode, date; no IP), `contact_reveals` (profile + date; no visitor data), `reports`, `restricted_terms` (flags, does not block), `erasure_fingerprints` (keyed hash of email and phone, expires after one year, counter), `app_settings` (review deadlines 7/3/1 business days, maximum therapies, text and photo limits, retention periods, controller contact), `rate_limit_hits` (hashed origin + 24 h window), `audit_log` (column names only, never personal values).

## 3. Profile changes: revisions
A therapist never writes to the live profile. Every change is a revision. Only an admin function applies it, in one transaction, after revalidating. The public keeps seeing the approved version meanwhile. Deadlines are counted from the last change and are configurable.

## 4. Public views, search and contact

### 4.1 Public reads
`anon` can read only two views (`security_invoker`): `public_profile_cards` (list) and `public_profile_detail` (profile page, including the website). **Phone and email appear in no view.** They are returned only by `reveal_contact`. Only country, region and city are shown, never a street address.

### 4.2 Result groups
- Group 1: profiles inside the chosen location.
- Group 2 (remote, outside the filter): "Other countries" if a country was chosen; "Other cities" and then "Other countries" if a region or city was chosen. It carries its own heading and a line saying these results are outside the chosen place; it does not rely on color alone.
- With mode "in person" there is no group 2.
- A search with no results in both groups is stored as an unmet search.
- No price sorting in Phase 1.

### 4.3 "From" rate on the card
Lowest rate of the audience that applies to the visitor (group 1: own country; group 2: other countries). One currency per audience in a profile; amounts are never converted or added. No rates: "Ask".

### 4.4 Contact
"Show contact" calls `reveal_contact` (rate limited per origin), records the event, and shows phone and email. The WhatsApp link is built only after that call, so the phone number is not in the page source before. The pre-filled message is generic and contains no health data. The email is displayed as text with a "Copy" button besides the `mailto:` link.

## 5. Foreign keys on delete
- Catalogs in use: `RESTRICT` (deactivate, never delete).
- Profile children (`profile_*`, `profile_revisions`): `CASCADE`.
- `moderation_events`, `contact_reveals`, `reports`: `SET NULL` (kept, anonymized).
- `people`: row is anonymized, not deleted. `person_roles`, `terms_acceptances`: `CASCADE`.
- `unmet_searches`: no foreign keys to people or profiles.

## 6. Erasure
1. A server action deletes the photo from both storage buckets (SQL cannot delete the files).
2. One `SECURITY DEFINER` function, in a single transaction: stores the fingerprint (one year), deletes content, contacts and revisions, anonymizes `people` and `moderation_events`, sets status `erased`, deletes the login user.
3. Required test: afterwards no table keeps email, phone, name or photo.

## 7. Access matrix (S select, I insert, U update, D delete, — none)
| Table | anon | Therapist | Admin |
|---|---|---|---|
| Catalogs and locations | S (view) | S | S/I/U |
| `therapist_profiles`, `profile_*` | S only through the 2 views | S own; **never U** (only via revision) | via function |
| `profile_contacts` (phone, email) | — (only `reveal_contact`) | S own | S |
| `profile_revisions` | — | S/I/U own, while open | S/U |
| `terms_acceptances` | — | S own; revoke via function | S |
| `moderation_events`, `audit_log`, `erasure_fingerprints`, `restricted_terms` | — | — | S |
| `reports` | I via function | — | S/U |
| `unmet_searches`, `contact_reveals`, `rate_limit_hits` | I only via function | — | S |
| `app_settings` | — | S public keys | S/U |

Writes by `anon` happen only through `log_search`, `reveal_contact` and the report function, each granted individually, with a fixed `search_path` and `session_user` checks. Privilege fields (status, approval, suspension) are protected by a trigger.

## Catalog access (commit 8)
Public catalogs (`languages`, `currencies`, `service_modes`, `session_formats`, `rate_audiences`, `location_levels`, `therapies` + translations, `locations` + translations): `anon` and `authenticated` can read **active rows only** (`authenticated` reads all, for the future admin panel). Internal catalogs (`contact_types`, `profile_statuses`, `revision_statuses`, `roles`): `authenticated` read only; `anon` has no grant. Nobody writes catalogs through the API: they change through migrations. Admin write policies arrive with the admin panel (they need `people` and `person_roles`). `service_role` has no grants on catalogs until a server feature needs them.
Sample therapies and locations live in `supabase/seed/dev-seed.sql` and are never applied to production.

## People access (commit 10)
`people` and `person_roles`: `anon` has no grant. `authenticated` reads only their own person row and roles; an admin (checked by `is_admin()`, a `SECURITY DEFINER` function with fixed `search_path`, executable only by `authenticated`) reads all. Nobody writes these tables through the API, so a user cannot give themselves a role. Erased people keep the row, anonymized (`erased_at` set, no email, no login link), enforced by a constraint.

## 8. Known risks
- High: a script harvesting phones. Mitigation: "Show contact" button, WhatsApp link after `reveal_contact`, rate limit per origin.
- High: the public views are everything `anon` can see; anonymous-access tests are required before closing any security change.
- High (legal): using therapists' data to offer other services needs an opt-in checkbox (unchecked by default, revocable) and a mention in the privacy policy. To verify per country.
- Medium: external website links can lead to cure claims; moderation reviews them and links use `rel="noopener noreferrer nofollow"`.
- Medium: erasure touches database and files; fixed order and retry.
- Medium: losing the HMAC key makes fingerprints unusable.

---

## Resumen en español
El modelo tiene 34 tablas: 14 catálogos, 12 de núcleo (persona, perfil vigente, terapias con tarifas, contactos, revisiones, moderación, aceptaciones) y 8 de operación (búsquedas sin resultado, revelado de contacto, denuncias, términos restringidos, huellas, ajustes, límite de pedidos, auditoría). El terapeuta nunca escribe sobre el perfil vigente: todo cambio es una revisión que aprueba el administrador. El público solo lee dos vistas; teléfono y mail salen únicamente por el botón "Ver contacto". Al eliminar un perfil se borra todo y queda solo una huella irreversible durante un año. Los catálogos se leen sin cuenta (solo filas activas) y no se escriben por la API: cambian por migración. La versión completa en español está en el Project (`terapeutas-modelo-datos-20261111_v03.md`).
