// One result: visual and short. Detail (formats, languages, prices, contact) is on the profile.
// Un resultado: visual y corto. El detalle (formatos, idiomas, precios, contacto) está en el perfil.

import Link from "next/link";
import { Avatar } from "@/components/avatar";
import { ModeIcon } from "@/components/mode-icon";
import { capItems, flagSrc } from "@/lib/card-view";
import type { SearchCard } from "@/lib/search";

const MAX_THERAPIES = 3;

export function ProfileCard({ card }: { card: SearchCard }) {
  const { shown, hidden } = capItems(card.therapyShorts, MAX_THERAPIES);
  const flag = flagSrc(card.countryIso);
  return (
    <article className="relative flex min-w-0 flex-col items-center rounded-2xl border border-linea bg-superficie p-6 text-center shadow-sm motion-safe:transition-shadow motion-safe:hover:shadow-md">
      {flag && (
        // Plain <img>: a small static SVG from /public; the country name is the accessible text. / <img> simple: un SVG chico y estático de /public; el nombre del país es el texto accesible.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={flag} alt={card.countryName ?? ""} title={card.countryName ?? undefined} width={32} height={24} loading="lazy" decoding="async" className="absolute right-4 top-4 h-6 w-8 rounded-sm object-cover ring-1 ring-linea" />
      )}
      {/* Avatar centered; the mode icons stack vertically at its right. / Avatar centrado; los íconos de modalidad apilados a su derecha. */}
      <div className="grid w-full grid-cols-[1fr_auto_1fr] items-center">
        <span aria-hidden="true" />
        <Avatar name={card.displayName} photoPath={card.photoPath} size="lg" />
        {card.serviceModes.length > 0 && (
          <ul className="flex flex-col items-start gap-2 pl-3" aria-label="Modo de atención">
            {card.serviceModes.map((mode) => (
              <li key={mode}>
                <ModeIcon mode={mode} />
              </li>
            ))}
          </ul>
        )}
      </div>
      <h3 className="mt-4 font-display text-xl font-semibold leading-tight text-tinta">{card.displayName}</h3>
      {card.isPinned && <p className="mt-0.5 text-xs font-medium text-acento">Fundador del sitio</p>}
      {card.headline && <p className="mt-2 line-clamp-2 text-sm text-tinta">{card.headline}</p>}
      {shown.length > 0 && (
        <ul className="mt-3 flex flex-wrap items-center justify-center gap-2" aria-label="Terapias">
          {shown.map((therapy, index) => (
            <li key={`${therapy}-${index}`} className="max-w-full truncate rounded-full bg-fondo px-3 py-1 text-sm text-tinta ring-1 ring-linea">
              {therapy}
            </li>
          ))}
          {hidden > 0 && <li className="text-sm text-apagado">y {hidden} más</li>}
        </ul>
      )}
      {card.place && <p className="mt-3 mb-5 text-sm text-apagado">{card.place}</p>}
      <Link
        className="mt-auto inline-flex min-h-10 items-center justify-center rounded-full bg-boton px-8 text-sm font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
        href={`/terapeuta/${card.profileId}`}
        aria-label={`Ver perfil de ${card.displayName}`}
      >
        Ver perfil
      </Link>
    </article>
  );
}
