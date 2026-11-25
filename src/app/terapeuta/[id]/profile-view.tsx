// The look of a therapist's profile, shared by the public page and by the therapist's own preview ("Ver cómo queda").
// In preview mode nothing can act: the contact button is off, the report form is hidden and the prices line has no date.
// El aspecto del perfil de un terapeuta, compartido por la página pública y por la vista previa del propio terapeuta ("Ver cómo queda").
// En modo vista previa nada puede actuar: el botón de contacto está apagado, el formulario de denuncia no se muestra y la línea de precios no lleva fecha.

import { Avatar } from "@/components/avatar";
import { CountryFlag } from "@/components/country-flag";
import { ModeBadge, ModeIcon } from "@/components/mode-icon";
import { SOCIAL_HOVER, SocialIcon } from "@/components/social-icon";
import { getTurnstileSiteKey } from "@/lib/env";
import { formatDate, formatMoney } from "@/lib/format";
import { joinWithY, labelLanguage, labelRateAudienceFor, labelSessionFormat } from "@/lib/labels";
import type { ProfileDetail, ProfileLinkKind, TherapyDetail } from "@/lib/profile-detail";
import { ContactReveal } from "./contact-reveal";
import { ReportForm } from "./report-form";

const LINK_LABELS: Record<ProfileLinkKind, string> = {
  website: "Sitio web",
  instagram: "Instagram",
  facebook: "Facebook",
  tiktok: "TikTok",
  youtube: "YouTube",
};

function TherapyBlock({ therapy, countryName }: { therapy: TherapyDetail; countryName: string | null }) {
  return (
    <li className="flex flex-col rounded-2xl border border-linea bg-superficie p-5 shadow-sm">
      {/* Title and mode icons on one row: the icons are explained once, above the list of therapies (see ModeLegend below).
          Título e íconos de modo en una fila: los íconos se explican una sola vez, arriba de la lista de terapias (ver ModeLegend más abajo). */}
      <div className="flex items-start justify-between gap-3">
        <h3 className="font-display text-xl font-semibold text-tinta">{therapy.name}</h3>
        {therapy.serviceModes.length > 0 && (
          <ul className="flex shrink-0 list-none gap-2 p-0" aria-label="Modo de atención">
            {therapy.serviceModes.map((mode) => (
              <li key={mode}><ModeIcon mode={mode} /></li>
            ))}
          </ul>
        )}
      </div>
      {therapy.description && <p className="mt-2 text-sm text-tinta">{therapy.description}</p>}
      <p className="mt-3 text-sm text-apagado">
        {[
          therapy.sessionFormats.length > 0 ? joinWithY(therapy.sessionFormats.map(labelSessionFormat)) : "",
          therapy.sessionMinutes ? `Sesión de ${therapy.sessionMinutes} min` : "",
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      {/* The prices sit at the bottom of the card, so they line up across cards of different height. / Los precios van al pie de la tarjeta, así quedan alineados aunque las tarjetas tengan distinta altura. */}
      <div className="mt-auto pt-3">
        {therapy.rates.length > 0 ? (
          <ul className="list-none border-t border-linea p-0 pt-3 text-sm text-tinta">
            {therapy.rates.map((rate) => (
              <li key={rate.audience} className="flex items-baseline justify-between gap-4 py-0.5">
                <span className="text-apagado">{labelRateAudienceFor(rate.audience, countryName)}</span>
                <span className="text-base font-semibold">{formatMoney(rate.amount, rate.currency)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="border-t border-linea pt-3 text-sm text-apagado">Precio: consultar con el terapeuta.</p>
        )}
      </div>
    </li>
  );
}

const MODE_ORDER = ["in_person", "remote"] as const;

// Says once what each icon means, only for the modes this therapist actually uses. / Dice una sola vez qué significa cada ícono, solo de los modos que este terapeuta usa.
function ModeLegend({ profile }: { profile: ProfileDetail }) {
  const present = MODE_ORDER.filter((mode) => profile.therapies.some((therapy) => (therapy.serviceModes as readonly string[]).includes(mode)));
  if (present.length === 0) return null;
  return (
    <p className="mt-2 flex flex-wrap items-center gap-x-5 gap-y-1 text-sm text-apagado">
      <span>Modo de atención:</span>
      {present.map((mode) => (
        <ModeBadge key={mode} mode={mode} bare />
      ))}
    </p>
  );
}

function RatesFreshness({ profile }: { profile: ProfileDetail }) {
  if (!profile.therapies.some((therapy) => therapy.rates.length > 0)) return null;
  const date = formatDate(profile.ratesConfirmedAt);
  return (
    <p className="mt-3 text-sm text-apagado">
      {profile.ratesCurrent && date
        ? `Precios al día · confirmados el ${date}`
        : date
          ? `Precios del ${date}: pueden haber cambiado`
          : "Precios sin fecha de confirmación"}
    </p>
  );
}

// photoUrl: the address of the photo when it is not the one in the public bucket (a pending photo, signed for a few minutes). / photoUrl: la dirección de la foto cuando no es la del bucket público (una pendiente, firmada por unos minutos).
export function ProfileView({ profile, preview }: { profile: ProfileDetail; preview?: { photoUrl?: string | null } }) {
  const siteKey = getTurnstileSiteKey();
  const h2 = "font-display text-2xl font-semibold text-tinta";
  return (
    <article>
      <header className="relative rounded-2xl border border-linea bg-superficie p-6 shadow-sm sm:flex sm:items-center sm:gap-6">
        <CountryFlag iso={profile.countryIso} name={profile.countryName} size="lg" />
        {/* Large photo (or initials when there is none). / Foto grande (o iniciales si no hay). */}
        <div className="flex justify-center sm:justify-start">
          <Avatar name={profile.displayName} photoPath={profile.photoPath} photoUrl={preview?.photoUrl} size="xl" />
        </div>
        <div className="mt-4 text-center sm:mt-0 sm:text-left">
          <h1 className="font-display text-3xl font-semibold leading-tight text-tinta">{profile.displayName}</h1>
          {profile.isPinned && <p className="mt-0.5 text-xs font-medium text-acento">Fundador del sitio</p>}
          {profile.headline && <p className="mt-2 text-tinta">{profile.headline}</p>}
          {profile.place && <p className="mt-1 text-sm text-apagado">{profile.place}</p>}
          <div className="mt-4">
            {preview ? (
              <div>
                <button type="button" disabled aria-describedby="preview-contact-note" className="min-h-10 rounded-full bg-boton px-6 text-sm font-semibold text-boton-texto opacity-60">
                  Ver contacto
                </button>
                <p id="preview-contact-note" className="mt-2 text-sm text-apagado">
                  En la vista previa el contacto no se muestra. Los pacientes lo ven al apretar este botón en tu perfil publicado.
                </p>
              </div>
            ) : siteKey ? (
              <ContactReveal profileId={profile.profileId} siteKey={siteKey} />
            ) : (
              <p className="text-sm text-apagado">El contacto directo no está disponible por ahora.</p>
            )}
          </div>
        </div>
      </header>

      {/* Therapies first (what, how, how much); the longer personal text comes after. / Primero las terapias (qué, cómo, cuánto); el texto personal, más largo, va después. */}
      {profile.therapies.length > 0 && (
        <section aria-labelledby="therapies-title" className="mt-8">
          <h2 id="therapies-title" className={h2}>Terapias</h2>
          <ModeLegend profile={profile} />
          <ul className="mt-3 grid list-none gap-4 p-0 sm:grid-cols-2">
            {profile.therapies.map((therapy) => (
              <TherapyBlock key={therapy.therapyId} therapy={therapy} countryName={profile.countryName} />
            ))}
          </ul>
          {!preview && <RatesFreshness profile={profile} />}
        </section>
      )}

      {profile.about && (
        <section aria-labelledby="sobre-mi-title" className="mt-8">
          <h2 id="sobre-mi-title" className={h2}>Sobre mí</h2>
          {/* plain text, line breaks kept; never HTML / texto plano, con saltos de línea; nunca HTML */}
          <p className="mt-3 whitespace-pre-line rounded-2xl border border-linea bg-superficie p-5 text-tinta shadow-sm">{profile.about}</p>
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

      {siteKey && !preview && (
        <section aria-label="Denunciar este perfil" className="mt-8">
          <ReportForm profileId={profile.profileId} siteKey={siteKey} />
        </section>
      )}
    </article>
  );
}
