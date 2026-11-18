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

Setup instructions will be added with the first runnable version.

## Resumen en español

Directorio gratuito y sin registro para pacientes: se elige una terapia y una zona, y el sistema muestra los terapeutas disponibles con su contacto. El sistema solo conecta, no gestiona turnos. Las búsquedas sin resultados se guardan como demanda no cubierta para invitar terapeutas donde hacen falta. Proyecto en desarrollo inicial.

## License

[MIT](LICENSE)
