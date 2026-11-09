# Holistic Therapist Finder

Search engine to find holistic therapists by therapy and location.

> **Status:** early development. The first public version (MVP) is being built in the open; this repository is updated as the work progresses.

## What is this?

Many people look for a holistic therapist (energy, quantum, bodywork, emotional and other complementary therapies) and do not know where to start. Therapists, in turn, struggle to be found.

This project is a free, no-sign-up directory:

- The **patient** picks a therapy and a place (country, region or city) and sees the therapists who offer it, with their contact details. No account is needed.
- The system **only creates the connection**. It does not book appointments or take payments.
- Searches that return no results are recorded as **unmet demand**, so new therapists can be invited where people are actually looking.

## Planned features (MVP)

- [ ] Catalog of therapies with categories and synonyms
- [ ] Search by therapy + location, with paginated results
- [ ] Public therapist profile (bio, therapies, languages, mode: in person / online, contact options)
- [ ] Contact-request tracking per therapist
- [ ] Log of searches with no results (demand signal)
- [ ] Therapist sign-up and personal dashboard to edit the profile
- [ ] Admin panel: profile moderation and therapy catalog
- [ ] Legal pages: medical disclaimer, terms, privacy

## Planned stack

- Next.js (App Router) + TypeScript
- Supabase (PostgreSQL, Auth, Storage, Row Level Security)
- Tailwind CSS
- Vercel for hosting
- Vitest / Playwright for tests, GitHub Actions for CI

## Design principles

- **Privacy first:** collect only what is necessary; no patient health data is stored.
- **Safe by default:** every profile is reviewed before it becomes public; no cure claims.
- **Mobile first:** most visitors will arrive from a phone.
- **No secrets in the repository:** configuration goes in environment variables (`.env.example` will list the required keys).

## Getting started

Setup instructions will be added with the first runnable version.

## Resumen en español

Directorio gratuito y sin registro para pacientes: se elige una terapia y una zona, y el sistema muestra los terapeutas disponibles con su contacto. El sistema solo conecta, no gestiona turnos. Las búsquedas sin resultados se guardan como demanda no cubierta para invitar terapeutas donde hacen falta. Proyecto en desarrollo inicial.

## License

[MIT](LICENSE)
