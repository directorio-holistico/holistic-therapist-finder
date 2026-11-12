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
`unmet_searches` (daily counter per therapy, location, mode; no IP), `contact_reveals` (daily counter per profile; no visitor data), `reports`, `restricted_terms` (flags, does not block), `erasure_fingerprints` (keyed hash of email and phone, expires after one year, counter), `app_settings` (review deadlines 7/3/1 business days, maximum therapies, text and photo limits, retention periods, controller contact), `rate_limit_hits` (hashed origin + 24 h window), `audit_log` (column names only, never personal values).

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

## Profile access (commit 11)
`therapist_profiles`, `profile_therapies`, `profile_languages`, `profile_service_modes`, `profile_session_formats`: `anon` has no grant (public profiles will come through two `security_invoker` views, later). `authenticated` reads only their own profile and links; an admin reads all. Nobody writes them through the API: the therapist changes a profile only through a revision that an admin approves. A trigger (`therapist_profiles_guard`) additionally stops API roles from inserting profiles or changing `person_id`, `status_id`, `approved_at` and `status_reason`, so a write grant or policy added by mistake later cannot expose them. The base location must be a city, and a published profile needs `approved_at`.

## Rates, contacts and settings (commit 12)
`profile_therapy_rates` and `profile_contacts`: same access as the other profile tables (own / admin read, no writes, nothing for `anon`). Phones and emails never reach `anon`; the only way out will be `reveal_contact`. A published profile must have a phone, cannot lose it, and `accepts_whatsapp` only applies to the phone. Rates: amount >= 0, decimals limited by the currency (CLP has none), one currency per audience within a profile. `app_settings`: `authenticated` reads public keys, an admin reads all and may change **only the `value` column** (a column-level grant, validated by a CHECK); keys are added by migration. `max_therapies_per_profile` (default 4) is enforced by a trigger.

## Initial therapy catalog (commit 13)
The initial catalog is a migration: 13 active therapies (energy and mind-body, plus quantum therapy, family constellations and akashic records) and 10 loaded but **hidden** ones (health practices regulated in many countries, or that sell products), pending a business decision. Only names are stored (in Spanish); descriptions are not, because Phase 1 has no description field and some wording would collide with the "no cure claims" rule. Visitors see only active therapies.

## Revisions, moderation and restricted terms (commit 14)
`profile_revisions`: the therapist reads their own and inserts/edits **drafts** of their own profile, only the columns `profile_id`, `payload` and `suggested_therapy` (column-level grants + RLS + a guard trigger). Workflow fields (status, flagged terms, priority, due date, rejection reason, closing date) are written only by server functions (next commit). One open revision per profile; nobody deletes revisions through the API. A rejection always carries its reason, and the therapist can read it. `moderation_events`: admin reads, nobody writes through the API; the action is the status it moved to. `restricted_terms`: admin reads and writes (the four policies); terms are stored lower case without accents and matched as whole words. **Restricted terms flag a revision, they never block it**: `find_restricted_terms(text)` lets a logged-in therapist check a text in advance and still send it; the admin sees the flagged terms in the queue. The starter list is provisional until the owner validates it.

## Revision submission (commit 15)
The therapist sends or discards a draft only through two `SECURITY DEFINER` functions (fixed `search_path`, executable only by `authenticated`): `submit_revision(id)` and `discard_revision(id)`. Identity comes from `auth.uid()`, never from a parameter; a revision that is not yours gives the same "not found" answer as one that does not exist. Submitting needs a draft, a non-empty payload with only known keys, and a profile that is not suspended or erased. Every text in the payload (nested too) and `suggested_therapy` is matched against restricted terms; the matches are stored in `flagged_terms` and returned, **never blocking** the send. The review deadline counts **business days** (Mon-Fri, Buenos Aires time, no holidays): 7 for a first submission, 3 for a change to an approved profile, 1 for high priority; all three are public settings (`review_days_initial`, `review_days_update`, `review_days_priority`, validated 1-30). `add_business_days` and `match_restricted_terms` are internal: no API role can run them. A generic test now fails if any `SECURITY DEFINER` function in `public` lacks a fixed `search_path` or if `PUBLIC` can execute any function.

## Revision decision (commit 16)
Only an administrator changes a live profile, and only through `approve_revision(id)` or `reject_revision(id, reason)` (`SECURITY DEFINER`, fixed `search_path`, executable only by `authenticated`, and each checks `is_admin()` inside). Approval is **all or nothing** in one transaction: the whole payload is validated (types, known keys, active catalog rows, photo path under the profile's own folder, city as base location, therapy limit, one currency per audience, valid phone) and then written to the live tables; any error leaves the profile and the revision untouched. A key present in the payload **replaces** that part of the profile; an absent key leaves it unchanged; `therapies` carry their own rates. The first approval of an unpublished profile publishes it and sets `approved_at` (kept on later approvals); a paused profile stays paused; suspended or erased profiles cannot be approved. A published profile cannot lose its phone through a revision. An admin cannot approve a revision of their own profile unless the setting `moderation_allow_self_approval` (private, boolean, default false) is true. A rejection needs a trimmed reason (1-1000 characters), which the therapist can read. Every decision writes one `moderation_events` row with the acting admin. `apply_revision_payload` and `revision_int` are internal: no API role can run them.

## Therapist registration (commit 17)
A 35th table, the catalog `legal_document_types` (terms, privacy, legal declaration = required; offers consent = optional), because catalogs are tables, not fixed lists. `terms_acceptances` is evidence: a person, a document, a version, `accepted_at` and `revoked_at`. A trigger makes it immutable (only `revoked_at` can go from null to a date, and only for optional documents); a revoked acceptance can be given again as a new row, so the history stays. Nobody writes it through the API; each person reads their own and the admin reads all. `register_therapist(name, {document: version})` (`SECURITY DEFINER`, `authenticated` only) needs a **verified email** (`auth.users.email_confirmed_at`), takes the email from the login (never from a parameter), and in one transaction creates the person, the `therapist` role, an empty unpublished profile and one acceptance per document; all required documents must be present, unknown ones are refused, the offers consent is absent unless given (unchecked by default). Registering twice, or with an email already used by another login, fails. `set_offers_consent(value, version)` gives or withdraws the optional consent. The local `auth.users` stub now has `email_confirmed_at`; to verify on the real project that Supabase fills it when the user opens the email link.

## Public display name (commit 18)
`therapist_profiles.display_name` (1-80 characters, no spaces around) is the name shown in search results. It starts as the person's name (a trigger copies it when the profile is created, cut to 80 characters) and changes only through a moderated revision (payload key `display_name`, checked against the restricted terms like the other texts). A published profile needs one. Why: the public views must show a name without reading `people`, which holds the emails, so no public role ever needs access to `people`. The guard trigger, `submit_revision` and `apply_revision_payload` were replaced (`create or replace`) keeping their permissions; the tests check them again.

## Public views (commit 19)
A visitor (`anon`) reads therapists only through two views, `public_profile_cards` (search result) and `public_profile_detail` (profile page), both `security_invoker` (they run with the visitor's own permissions, so the grants below are what really limits them). Because of that, `anon` also has **column-level** read access, with a policy that keeps only published rows, on seven tables: `therapist_profiles` (id, location, display name, zone, headline, start year, photo path, approval date; never `person_id`, status, status reason), `profile_therapies`, `profile_languages`, `profile_service_modes`, `profile_session_formats`, `profile_therapy_rates`, and `profile_contacts` (only the website: a contact type that is not private). **Phone and email are in no view and no policy reaches them**; they will come out only through `reveal_contact`. Two read-only helpers (`is_published_profile`, `public_contact_code`) let the policies ask without giving `anon` the internal catalogs. Public pages are rendered with `anon`; a logged-in user querying the views sees only their own published profile (the admin sees all published ones). Names come from the Spanish translations (the only interface language for now). Test 12 compares the exact list of what `anon` can read against a written list, scans every row of both views for canary strings (phone, email, legal name, status reason), and checks that paused, suspended and unpublished profiles and deactivated therapies disappear at once. Known cost: each row calls a small function in the policy; fine for Phase 1 volumes, to measure before scaling.

## Search and unmet searches (commit 20)
`search_profiles(therapy, location, mode?, limit, offset)` is the only way the website searches. It is `SECURITY INVOKER` and reads **only** `public_profile_cards`, executable by `anon` only (a logged-in user would see just their own profile through the view, so the website always searches with the `anon` role). A search needs a therapy and a place (country, region or city); the service mode is an optional filter. Results come in three groups, with a stable order (group, approval date, id; never by price): **1** profiles inside the chosen place; **2** remote profiles of the same country outside it (only when a region or city was chosen); **3** remote profiles of other countries. With the in-person filter there are only profiles of group 1. Every row carries `total_count`, so the page knows the full size. Limit 1-50, offset 0-10000; any invalid input fails with 22023. The codes `in_person` and `remote` of `service_modes` carry the grouping rule (test 13 checks they exist).

`unmet_searches` is an **aggregated daily counter** (therapy, place, mode, UTC day, count) instead of one row per visit: no IP, no identifier, nothing that points to a person, and a visitor cannot inflate the table with new rows. This is a deliberate change from the first model (one row per search). `log_search(therapy, place, mode?)` (`SECURITY DEFINER`, `anon` only) records only when the search truly has no result in any group; otherwise it returns false and stores nothing. Only the admin reads the table; nobody writes it through the API. The website must never block results if logging fails. Retention: `purge_expired_unmet_searches()` (service role only) deletes counters older than the private setting `retention_unmet_searches_months` (12 by default, 1-120). Rate limiting by origin is **not** here: the database cannot see the visitor's address when the website server makes the call; it needs its own decision (ADR) before the table `rate_limit_hits`. Test 13 covers the groups for country, region and city, each filter, pagination, validation, the counters and the retention; 15 deliberate weakenings of the code were each caught by some test.

## Contact reveal (commit 21)
Phone and email (the contact types marked private) leave the database **only** through `reveal_contact(profile_id)`: `SECURITY DEFINER`, fixed `search_path`, executable by `anon` only. It returns `contact_type`, `value` and `accepts_whatsapp` for a **published** profile; the website (public, already in the view) is not part of it. An unpublished, paused, suspended, unknown or null profile returns no rows and records nothing, so the answer does not reveal whether a hidden profile exists. Deactivated contact types are not returned. Every call that returns contacts adds 1 to `contact_reveals`, a **daily counter per profile** (UTC day; no IP, no visitor data, no contact type), read only by the admin and written by nobody through the API; deleting a profile deletes its counters (cascade), so erasure leaves no residue. This also replaces the "one row per reveal" of the first model, for the same privacy reason as `unmet_searches`. Retention: `purge_expired_contact_reveals()` (service role only) with the private setting `retention_contact_reveals_months` (12 by default). Rate limiting by origin is still pending its own decision (ADR): until then a script could call `reveal_contact` profile by profile, which is the main reason the ADR comes before publishing. **Update (commit 24): this door is now closed; the only caller is the website server through `reveal_contact_limited`.** Test 14 covers what is returned and what is not, every role, the counters, the deactivated types, the retention and the cascade; 15 deliberate weakenings of the code were each caught.

## Reports and suspension (commit 22)
Three new tables: `reports` and two catalogs, `report_reasons` (cure claim, false information, inappropriate content, impersonation, unsafe practice, other) and `report_statuses` (open, dismissed, resolved); catalogs are tables, not fixed lists. A report holds the profile, the reason, optional details (1-1000 characters), an optional reporter email (lower case, validated; no account is needed, RN-11), the status, the dates and, when closed, who closed it and a written note. A check keeps the closing date and the note together. **Only the website server (`service_role`) creates a report**, through `report_profile`: it takes the same bot check and per-origin limit as the contact reveal (ADR-0003), so no API role can flood the table. An unknown, hidden or null profile gets the same error ("unknown profile"); only published profiles can be reported. Only the admin reads reports (not even the therapist reported sees them) and nobody writes the table through the API.

The admin closes a report with `close_report(id, 'dismissed' | 'resolved', note)` (note required; only an open report can be closed; it records who and when). **Closing a report does not touch the profile**: suspending is a separate, explicit decision. `suspend_profile(id, reason)` (reason 1-500 characters, the limit of `status_reason`) works from unpublished, published or paused and refuses suspended or erased profiles; `reinstate_profile(id, reason)` sends a suspended profile back to published if it had been approved before, or to unpublished if never; the same guard trigger as always still demands a phone and a location. Both write one `moderation_events` row (who, when, why) and are `SECURITY DEFINER`, check `is_admin()` inside, and are executable by `authenticated` only. A suspended profile disappears from the public views at once.

Retention: `purge_expired_reports()` (service role only) deletes **closed** reports older than the private setting `retention_reports_months` (12, **proposed, not yet confirmed by the owner**); open reports are never purged. Deleting a profile keeps its reports with no profile (`SET NULL`); the erasure commit must also clear the free-text `details` of those reports, because they can name the therapist. Test 15 covers every role against every function, the validations, the records, the visibility, the retention and the cascade; 28 deliberate weakenings of the code were each caught.

## Erasure of a therapist (commit 23)
Erasing a therapist **deletes** the profile and everything that hangs from it (contacts, therapies, rates, languages, modes, revisions and reveal counters, by cascade) and **anonymizes** the person row: name replaced by "Persona eliminada", email and login link cleared (the constraint `people_erased_shape` already demanded that shape), roles removed. Reports about the profile stay without a profile, but their free-text `details` are erased (they can name the therapist); the reporter's optional email stays until the retention of closed reports, because it is another person's data. What also stays: the acceptance history and the moderation records (who decided, when, why; no link to the profile), both without personal data once the person is anonymized, and **a fingerprint** of each email and phone.

The fingerprint is a keyed hash (HMAC-SHA256) **computed by the website server** with a secret key that never reaches the database; the database only stores 64 hex characters per email or phone, with a type, a counter, the dates and an expiry of **12 months** (decided by the owner; setting `retention_erasure_fingerprints_months`). It links to no person row and cannot be reversed without the key. Purpose: if the same email or phone comes back (`check_erasure_fingerprints`), the server knows it was erased before and how many times, to flag it for the admin (for example someone who erases to escape a suspension). A repeated erasure adds to the counter and renews the expiry; a fingerprint already expired but not yet purged restarts at 1. Emails are normalized to lower case and phones to digits only before hashing (`erasure_material` gives the server those values). Losing the key makes old fingerprints useless (they would never match again) but exposes nothing.

Everything runs through four functions executable **only by the server** (`service_role`): `erasure_material`, `erase_therapist(person, fingerprints, 'self' | 'admin')` (one transaction; refuses an administrator, an already erased person and invalid fingerprints; writes a moderation record with no profile link), `check_erasure_fingerprints` and `purge_expired_erasure_fingerprints`. No API role, not even the admin, runs them or reads the table: the server first verifies WHO asks (the therapist for their own profile, or an admin), then calls. `erase_therapist` returns the old login user id and the photo path so the server finishes: **1)** database (done), **2)** delete the user in Auth, **3)** delete the photo files. If 2 or 3 fail the data is already gone from the database; a later cleanup job removes orphans (Auth users without a person, photo folders without a profile). Test 16 scans every row of every public table for the therapist's data before and after (a canary string in 5 tables) and checks the roles, the counters, the expiry and the old login; 35 deliberate weakenings were caught by some test, 2 survive for a good reason (the code validates twice; an erased person has no email or profile anyway), and the test found a real bug on the way (`check_erasure_fingerprints` did not validate its input when the table was empty).

## Rate limit by origin and the closed door (commit 24)
The direct door is **closed**: since this commit **no API role** (`anon`, `authenticated`, not even `service_role`) can run `reveal_contact`; before, `anon` could, and the `anon` key is public, so a script could harvest every phone profile by profile. The only door is `reveal_contact_limited(profile_id, origin_hash)`, executable **only by the website server** (`service_role`). The server reads the visitor's address, verifies the Cloudflare Turnstile token and computes the **origin hash** (HMAC-SHA256 with a secret key kept in server variables; IPv4 whole, IPv6 cut to /64); the database receives only 64 hex characters, never an address. This design is ADR-0003.

The 36th table, `rate_limit_hits`, holds one row per action, origin hash and UTC day with a counter (`action` is a free code, today only `reveal`; the same table will serve the report limit). It has RLS on, **no grants and no policies**: nobody reads or writes it through the API, not even the admin (pseudonymous data with no use for a person). The function counts and reveals **in one transaction**, and the count is **one atomic statement** (`INSERT ... ON CONFLICT DO UPDATE ... WHERE hits < limit`), so two simultaneous calls cannot both take the last slot. Every valid call counts, **even for a hidden, unknown or null profile**, so guessing ids is not free. Over the limit it raises the dedicated error `RL429` ("rate limit reached") and reveals and counts nothing. An invalid hash (null, upper case, wrong length, an address) raises 22023 and stores nothing. The limit is the private setting `reveal_daily_limit` (**20**, decided by the owner, valid 1-10000); a missing setting **closes** the door instead of opening it. The window is a fixed UTC day (near midnight up to twice the limit can pass; accepted in the ADR). `purge_expired_rate_limit_hits()` (service role only) deletes counters older than `retention_rate_limit_days` (2, valid 1-30).

Not in this commit (website, later): the route `POST /api/reveal`, the Turnstile check, the HMAC, the Vercel WAF rule. `report_profile` is still callable by `service_role` without a limit: the server route must apply the same gate (the table already accepts another `action`). Test 14 was adapted (the caller is now `service_role` through `reveal_contact_limited`; it also checks that no API role runs `reveal_contact`). Test 17 covers the limit, the isolation between origins, profiles, days and actions, the error code, the hash validation, the settings, every role against every function and the table, and the purge; 50 deliberate weakenings of the code were each caught.

## Audit log (commit 25)
The 37th and last table of Phase 1, `audit_log`, records **who changed what and when** on the six tables that hold identity, privileges or live content: `people`, `person_roles`, `therapist_profiles`, `profile_contacts`, `app_settings` and `restricted_terms`. A trigger writes one row after each insert, update or delete, **in the same transaction** (a change that rolls back takes its record with it). It stores the table, the operation, the row key (ids only, never names), the time, the acting person (`actor_person_id`, from the login; null if none) and the acting role (`actor_role`: `authenticated` for a logged-in user, `service_role` for the website server, null for migrations and manual work as owner). No IP and no user agent.

**No personal value is stored.** For an update it keeps only the **names of the columns that changed** (`full_name`, `email`, `status_id`...), never the old or new content; an update that changes nothing leaves no record. So erasing a therapist leaves nothing personal here (test 18 scans the whole table after an erasure, and test 16 scans it again with the others). The only exception is `app_settings`, which keeps the old and new **value** (numbers and booleans, nothing personal), because "someone changed `reveal_daily_limit`" is useless without them; a check forbids `detail` on any other table.

The log is **append-only, even for the table owner**: a trigger refuses update, delete and truncate; the retention purge is the only way out. Only the admin reads it; nobody writes it through the API (not even `service_role`). It has **no foreign key** to `people` on purpose: an FK with `ON DELETE SET NULL` would try to update the log. Retention: `purge_expired_audit_log()` (service role only) deletes rows older than `retention_audit_months` (**24, proposed, to be confirmed by the owner**; configurable 1-120). A few things it does not cover: changes made as the database owner in the SQL editor appear with a null role (they are visible, but not attributed to a role); revisions and moderation decisions already have their own record (`moderation_events`), so they are not duplicated here; and, like all admin reads, the audit view must be paginated (the 1,000-row limit).

Test 18 covers the audited set (exactly six, AFTER ROW), every kind of record, the key of composite primary keys, the attribution by role, the absence of personal values, every role against the table and the functions, the append-only rule, the retention and the missing setting; 69 deliberate weakenings of the code were each caught (8 survived at first and led to new checks: a comparison that hid a null, the key of a changed row, the values of a setting insert and delete, and the missing foreign key).

Tables: 37, all of Phase 1 (the two report catalogs were added to the 35 planned). The database design is complete; what remains is to apply it to the real Supabase project, Storage for photos, and the application.

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
