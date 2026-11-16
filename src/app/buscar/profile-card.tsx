// One result: visual and short. Detail (headline, formats, languages, prices, contact) is on the profile.
// Un resultado: visual y corto. El detalle (presentación, formatos, idiomas, precios, contacto) está en el perfil.

import Link from "next/link";
import { Avatar } from "@/components/avatar";
import { ModeIcon } from "@/components/mode-icon";
import { capItems } from "@/lib/card-view";
import type { SearchCard } from "@/lib/search";

const MAX_THERAPIES = 3;

export function ProfileCard({ card }: { card: SearchCard }) {
  const { shown, hidden } = capItems(card.therapyShorts, MAX_THERAPIES);
  return (
    <article className="flex min-w-0 flex-col items-center rounded-2xl border border-linea bg-superficie p-6 text-center shadow-sm motion-safe:transition-shadow motion-safe:hover:shadow-md">
      <Avatar name={card.displayName} size="lg" />
      <h3 className="mt-4 font-display text-xl font-semibold leading-tight text-tinta">{card.displayName}</h3>
      {card.isPinned && <p className="mt-0.5 text-xs font-medium text-acento">Fundador del sitio</p>}
      {card.place && <p className="mt-1 text-sm text-apagado">{card.place}</p>}
      {shown.length > 0 && (
        <ul className="mt-4 flex flex-wrap items-center justify-center gap-2" aria-label="Terapias">
          {shown.map((therapy, index) => (
            <li key={`${therapy}-${index}`} className="max-w-full truncate rounded-full bg-fondo px-3 py-1 text-sm text-tinta ring-1 ring-linea">
              {therapy}
            </li>
          ))}
          {hidden > 0 && <li className="text-sm text-apagado">y {hidden} más</li>}
        </ul>
      )}
      {card.serviceModes.length > 0 && (
        <ul className="mt-4 flex justify-center gap-2" aria-label="Modo de atención">
          {card.serviceModes.map((mode) => (
            <li key={mode}>
              <ModeIcon mode={mode} />
            </li>
          ))}
        </ul>
      )}
      <Link
        className="mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-full border border-tinta px-5 text-sm font-semibold text-tinta hover:bg-fondo focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
        href={`/terapeuta/${card.profileId}`}
        aria-label={`Ver perfil de ${card.displayName}`}
      >
        Ver perfil
      </Link>
    </article>
  );
}
