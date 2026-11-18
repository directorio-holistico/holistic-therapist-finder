# Holistic Therapist Finder

Search engine to find holistic therapists by therapy and location.

> **Status:** pre-launch. The site is deployed at <https://faroholistico.com> and is under active development in the open; therapists are not being onboarded yet. This repository is updated as the work progresses.

## What is this?

Many people look for a holistic therapist (energy, quantum, bodywork, emotional and other complementary therapies) and do not know where to start. Therapists, in turn, struggle to be found.

This project is a free, no-sign-up directory:

- The **patient** picks a therapy and a place (country, region or city) and sees the therapists who offer it, with their contact details. No account is needed.
- The system **only creates the connection**. It does not book appointments or take payments.
- Searches that return no results are meant to be recorded as **unmet demand**, so new therapists can be invited where people are actually looking.

## Features (MVP)

- [x] Catalog of therapies (database tables; names are translatable by design)
- [x] Search by therapy + location, with an "all" option
- [x] Public therapist profile (about me, therapies with mode and format per therapy, "from" rates, contact on request)
- [x] Contact reveal on request: bot check (Cloudflare Turnstile), daily limit per origin, no patient data stored
- [x] Therapist sign-up and personal dashboard (email-link sign-in with own password, profile editor, optional photo with explicit consent)
- [x] Moderation: every profile change is a revision that the admin reviews; admin screens for revisions and reports
- [x] Public reports: anyone can report a profile (bot check and rate limit)
- [x] Legal pages: legal notice, terms of use, privacy policy and cookies policy (plus the therapist declaration at sign-up)
- [ ] Log of searches with no results (demand signal)
- [ ] Admin screens for the therapy catalog (catalog changes are database migrations for now)

## Stack

- Next.js 16 (App Router) + React 19 + TypeScript (strict)
- Supabase (PostgreSQL, Auth, Storage, Row Level Security)
- Tailwind CSS 4, Zod 4, sharp (image processing)
- Vitest for unit tests, SQL test suites for the database, GitHub Actions for CI
- Vercel for hosting, Cloudflare Turnstile as bot check
- Planned: Playwright end-to-end tests

## Design principles

- **Privacy first:** collect only what is necessary; no patient health data is stored.
- **Safe by default:** every profile is reviewed before it becomes public; no cure claims.
- **Mobile first:** most visitors will arrive from a phone.
- **No secrets in the repository:** configuration goes in environment variables (`.env.example` lists the required keys, with empty values).
- **Database first:** schema changes are versioned SQL migrations (`supabase/migrations`), with row-level security, tests and verification queries.

## Free-plan limits / Límites de los planes gratuitos

The project runs on free plans on purpose. These are the limits that matter and what happens when they are reached.
*El proyecto usa planes gratuitos a propósito. Estos son los límites que importan y qué pasa al alcanzarlos.*

| Service | Used for | Free-plan limit | Note |
| --- | --- | --- | --- |
| Resend | Transactional email (sign-in links) | 100 emails/day, 3,000/month | Sending pauses when the cap is reached. |
| Supabase Auth | The same emails, through custom SMTP | Default limit of 30 emails/hour *(to verify in the dashboard)* | Raising it is a dashboard setting. |
| Supabase | Database, Auth, Storage | The project pauses after 7 days of inactivity; no scheduled backups on the Free plan | Backup and keep-alive plan pending (ADR-0002). |
| ImprovMX | Forwards mail sent to the contact address | 500 forwarded emails/day, 25 aliases, 1 domain | Receive-only: it cannot send. |
| Vercel | Hosting | Hobby plan: personal, non-commercial use *(to verify)* | Hosting decision pending (ADR-0002). |

- **Resend:** 100 mails por día y 3.000 por mes; al llegar al tope se pausa el envío.
- **Supabase Auth:** límite por defecto de 30 mails por hora (a verificar en el panel).
- **Supabase:** el proyecto se pausa tras 7 días sin actividad y el plan gratuito no incluye copias de seguridad programadas; el plan de respaldo está pendiente (ADR-0002).
- **ImprovMX:** 500 reenvíos por día, 25 alias y 1 dominio; solo recibe, no envía.
- **Vercel:** el plan Hobby es para uso personal no comercial (a verificar); la decisión de hosting está pendiente (ADR-0002).

## Legal texts / Textos legales

The legal pages (legal notice, terms of use, privacy policy and cookies policy) were drafted with AI assistance. A review by a lawyer is in progress and they may change. They are not legal advice.
*Las páginas legales (aviso legal, términos de uso, política de privacidad y de cookies) se redactaron con asistencia de IA. Hay una revisión por un abogado en curso y pueden cambiar. No constituyen asesoramiento legal.*

## Getting started

Requirements: Node.js 20.9 or newer, and a Supabase project (see [`docs/supabase-setup.md`](docs/supabase-setup.md) and [`docs/auth-setup.md`](docs/auth-setup.md)).

```bash
git clone https://github.com/directorio-holistico/holistic-therapist-finder.git
cd holistic-therapist-finder
npm install
cp .env.example .env.local   # on Windows: copy .env.example .env.local
npm run dev
```

Fill `.env.local` with your own values. **Never commit it.** The variables are validated in `src/lib/env.ts`:

| Variable | Where it is used |
| --- | --- |
| `NEXT_PUBLIC_SITE_URL` | Public address of the site (`http://localhost:3000` in development) |
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase public values (the anon/publishable key only) |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only. Never expose it to the browser |
| `FINGERPRINT_HMAC_KEY`, `RATE_LIMIT_HMAC_KEY` | Server only. Secrets for irreversible fingerprints and the daily rate limit (random, 32+ characters, all different) |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` | Cloudflare Turnstile. Use Cloudflare's dummy keys for local tests |
| `CONTROLLER_CONTACT_EMAIL` | Contact shown in the legal pages |

Scripts:

| Command | What it does |
| --- | --- |
| `npm run dev` | Development server |
| `npm run build` / `npm start` | Production build / run it |
| `npm test` | Unit tests (Vitest) |
| `npm run typecheck` | `next typegen` and `tsc --noEmit` |
| `npm run lint` | ESLint |

Database helpers (PowerShell, Windows) live in `scripts/db/`: `Reset-LocalDb.ps1` and `Test-LocalDb.ps1` for a local Postgres, `Apply-Remote.ps1` and `Gen-Types.ps1` for the Supabase project, `Test-RemoteAnon.ps1` and `Test-RemoteIsolation.ps1` for the access tests, and `Demo-Remote.ps1` for fictional demo data. `ci-sql-tests.sh` runs the SQL suites in CI. Read the header of each script before running it.

## Documentation

- [`docs/data-model.md`](docs/data-model.md): tables and relations
- [`docs/glossary.md`](docs/glossary.md): one word per concept
- [`docs/decisions/`](docs/decisions): architecture decision records (ADR)
- [`docs/legal-review-checklist.md`](docs/legal-review-checklist.md): checklist for the legal review

## Resumen en español

Directorio gratuito y sin registro para pacientes: se elige una terapia y una zona, y el sistema muestra los terapeutas disponibles con su contacto. El sistema solo conecta, no gestiona turnos. Las búsquedas sin resultados se guardarán como demanda no cubierta para invitar terapeutas donde hacen falta.

**Estado:** previo al lanzamiento. El sitio está desplegado en <https://faroholistico.com> y en desarrollo activo; todavía no se incorporan terapeutas.

**Qué funciona hoy:** catálogo de terapias, búsqueda por terapia y zona, perfil público, "Ver contacto" con verificación anti-bots y límite diario, alta y panel del terapeuta (con foto opcional y consentimiento), moderación de cada cambio de perfil, denuncias públicas y páginas legales. **Pendiente:** registro de búsquedas sin resultado y administración del catálogo de terapias.

**Cómo correrlo:** Node.js 20.9 o superior, un proyecto de Supabase, copiar `.env.example` a `.env.local`, completar los valores (nunca subirlo al repositorio) y ejecutar `npm install` y `npm run dev`. Los límites de los planes gratuitos están en la sección de arriba.

## License

[MIT](LICENSE)
