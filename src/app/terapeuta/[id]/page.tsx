// Public profile of a therapist. Everything the patient needs to know about the therapist, therapy by therapy. The phone and
// the mail are NOT in the page: they come only through the "Ver contacto" button (ADR-0003).
// Perfil público de un terapeuta. Todo lo que el paciente necesita saber, terapia por terapia. El teléfono y el mail NO
// están en la página: llegan solo con el botón "Ver contacto" (ADR-0003).

import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { Avatar } from "@/components/avatar";
import { HealthNotice } from "@/components/health-notice";
import { ModeBadge } from "@/components/mode-icon";
import { SiteHeader } from "@/components/site-header";
import { SOCIAL_HOVER, SocialIcon } from "@/components/social-icon";
import { getTurnstileSiteKey } from "@/lib/env";
import { formatDate, formatMoney } from "@/lib/format";
import { joinWithY, labelLanguage, labelRateAudience, labelSessionFormat } from "@/lib/labels";
import { loadPublicProfile, type ProfileDetail, type ProfileLinkKind, type TherapyDetail } from "@/lib/profile-detail";
import { createAnonClient } from "@/lib/supabase/anon-client";
import { ContactReveal } from "./contact-reveal";
import { ReportForm } from "./report-form";

export const metadata: Metadata = { title: "Perfil del terapeuta" };

type PageProps = { params: Promise<{ id: string }> };

const LINK_LABELS: Record<ProfileLinkKind, string> = {
  website: "Sitio web",
  instagram: "Instagram",
  facebook: "Facebook",
  tiktok: "TikTok",
  youtube: "YouTube",
};

function TherapyBlock({ therapy }: { therapy: TherapyDetail }) {
  return (
    <li className="rounded-2xl border border-linea bg-superficie p-5 shadow-sm">
      <h3 className="font-display text-xl font-semibold text-tinta">{therapy.name}</h3>
      {therapy.description && <p className="mt-2 text-sm text-tinta">{therapy.description}</p>}
      {therapy.serviceModes.length > 0 && (
        <ul className="mt-3 flex list-none flex-wrap gap-2 p-0" aria-label="Modo de atención">
          {therapy.serviceModes.map((mode) => (
            <li key={mode}><ModeBadge mode={mode} /></li>
          ))}
        </ul>
      )}
      <p className="mt-3 text-sm text-apagado">
        {[
          therapy.sessionFormats.length > 0 ? joinWithY(therapy.sessionFormats.map(labelSessionFormat)) : "",
          therapy.sessionMinutes ? `Sesión de ${therapy.sessionMinutes} min` : "",
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      {therapy.rates.length > 0 ? (
        <ul className="mt-3 list-none border-t border-linea p-0 pt-3 text-sm text-tinta">
          {therapy.rates.map((rate) => (
            <li key={rate.audience} className="flex items-baseline justify-between gap-4 py-0.5">
              <span className="text-apagado">{labelRateAudience(rate.audience)}</span>
              <span className="text-base font-semibold">{formatMoney(rate.amount, rate.currency)}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 border-t border-linea pt-3 text-sm text-apagado">Precio: consultar con el terapeuta.</p>
      )}
    </li>
  );
}

function RatesFreshness({ profile }: { profile: ProfileDetail }) {
  if (!profile.therapies.some((therapy) => therapy.rates.length > 0)) return null;
  const date = formatDate(profile.ratesConfirmedAt);
  return (
    <p className="mt-3 text-xs text-apagado">
      {profile.ratesCurrent && date
        ? `Precios al día · confirmados el ${date}`
        : date
          ? `Precios del ${date}: pueden haber cambiado`
          : "Precios sin fecha de confirmación"}
    </p>
  );
}

function ProfileView({ profile }: { profile: ProfileDetail }) {
  const siteKey = getTurnstileSiteKey();
  const h2 = "font-display text-2xl font-semibold text-tinta";
  return (
    <article>
      <header className="rounded-2xl border border-linea bg-superficie p-6 shadow-sm sm:flex sm:items-center sm:gap-6">
        {/* Large photo (or initials when there is none). / Foto grande (o iniciales si no hay). */}
        <div className="flex justify-center sm:justify-start">
          <Avatar name={profile.displayName} photoPath={profile.photoPath} size="xl" />
        </div>
        <div className="mt-4 text-center sm:mt-0 sm:text-left">
          <h1 className="font-display text-3xl font-semibold leading-tight text-tinta">{profile.displayName}</h1>
          {profile.isPinned && <p className="mt-0.5 text-xs font-medium text-acento">Fundador del sitio</p>}
          {profile.headline && <p className="mt-2 text-tinta">{profile.headline}</p>}
          {profile.place && <p className="mt-1 text-sm text-apagado">{profile.place}</p>}
          <div className="mt-4">
            {siteKey ? (
              <ContactReveal profileId={profile.profileId} siteKey={siteKey} />
            ) : (
              <p className="text-sm text-apagado">El contacto directo no está disponible por ahora.</p>
            )}
          </div>
        </div>
      </header>

      {profile.about && (
        <section aria-labelledby="sobre-mi-title" className="mt-8">
          <h2 id="sobre-mi-title" className={h2}>Sobre mí</h2>
          {/* plain text, line breaks kept; never HTML / texto plano, con saltos de línea; nunca HTML */}
          <p className="mt-3 whitespace-pre-line rounded-2xl border border-linea bg-superficie p-5 text-tinta shadow-sm">{profile.about}</p>
        </section>
      )}

      {profile.therapies.length > 0 && (
        <section aria-labelledby="therapies-title" className="mt-8">
          <h2 id="therapies-title" className={h2}>Terapias</h2>
          <ul className="mt-3 grid list-none gap-4 p-0 sm:grid-cols-2">
            {profile.therapies.map((therapy) => (
              <TherapyBlock key={therapy.therapyId} therapy={therapy} />
            ))}
          </ul>
          <RatesFreshness profile={profile} />
        </section>
      )}

      {(profile.languages.length > 0 || profile.practiceStartYear !== null) && (
        <section aria-labelledby="about-title" className="mt-8">
          <h2 id="about-title" className={h2}>Datos</h2>
          <ul className="mt-3 list-none rounded-2xl border border-linea bg-superficie p-5 text-tinta shadow-sm">
            {profile.languages.length > 0 && <li>Idiomas: {profile.languages.map(labelLanguage).join(", ")}</li>}
            {profile.practiceStartYear !== null && <li>Terapeuta desde {profile.practiceStartYear}</li>}
          </ul>
        </section>
      )}

      {profile.links.length > 0 && (
        <section aria-labelledby="links-title" className="mt-8">
          <h2 id="links-title" className={h2}>Redes y sitio web</h2>
          <ul className="mt-3 flex list-none flex-wrap gap-3 p-0">
            {profile.links.map((link) => (
              <li key={link.kind}>
                <a
                  href={link.href}
                  target="_blank"
                  rel="noopener noreferrer nofollow"
                  title={`${LINK_LABELS[link.kind]}: ${link.text}`}
                  className={`inline-flex size-11 items-center justify-center rounded-full border border-linea bg-superficie text-tinta shadow-sm motion-safe:transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento ${SOCIAL_HOVER[link.kind]}`}
                >
                  <SocialIcon kind={link.kind} />
                  <span className="sr-only">{LINK_LABELS[link.kind]}: {link.text}</span>
                </a>
              </li>
            ))}
          </ul>
        </section>
      )}

      {siteKey && (
        <section aria-label="Denunciar este perfil" className="mt-8">
          <ReportForm profileId={profile.profileId} siteKey={siteKey} />
        </section>
      )}
    </article>
  );
}

async function ProfileContent({ params }: PageProps) {
  const { id } = await params;
  const profile = await loadPublicProfile(createAnonClient(), id);
  if (!profile) notFound();
  return <ProfileView profile={profile} />;
}

export default function ProfilePage({ params }: PageProps) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-3xl px-4 py-8">
        <p className="mb-4">
          <Link className="text-sm text-apagado underline hover:text-tinta" href="/buscar">← Volver a la búsqueda</Link>
        </p>
        <Suspense fallback={<p className="text-apagado">Cargando el perfil…</p>}>
          <ProfileContent params={params} />
        </Suspense>
        <HealthNotice className="mt-10" />
      </main>
    </>
  );
}
