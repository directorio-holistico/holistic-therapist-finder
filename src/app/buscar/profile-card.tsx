// One result. The contact data is NOT here: it is shown only through the contact reveal (later commit).
// Un resultado. Los datos de contacto NO están acá: se muestran solo con la revelación de contacto (commit posterior).

import Link from "next/link";
import { formatDate, formatMoney } from "@/lib/format";
import { joinWithY, labelLanguage, labelRateAudience, labelServiceMode, labelSessionFormat } from "@/lib/labels";
import type { SearchCard } from "@/lib/search";

function RatesLine({ card }: { card: SearchCard }) {
  if (card.rates.length === 0) return <p className="text-sm text-zinc-600 dark:text-zinc-400">Precios: consultar con el terapeuta.</p>;
  const date = formatDate(card.ratesConfirmedAt);
  return (
    <div className="text-sm text-zinc-700 dark:text-zinc-300">
      <ul className="list-none p-0">
        {card.rates.map((rate) => (
          <li key={rate.audience}>
            {labelRateAudience(rate.audience)}: desde {formatMoney(rate.amount, rate.currency)}
          </li>
        ))}
      </ul>
      <p className="mt-1 text-xs text-zinc-600 dark:text-zinc-400">
        {card.ratesCurrent && date
          ? `Precios al día · confirmados el ${date}`
          : date
            ? `Precios del ${date}: pueden haber cambiado`
            : "Precios sin fecha de confirmación"}
      </p>
    </div>
  );
}

export function ProfileCard({ card }: { card: SearchCard }) {
  return (
    <article className="rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
      <h3 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">{card.displayName}</h3>
      {card.isPinned && <p className="text-xs text-zinc-600 dark:text-zinc-400">Fundador del sitio</p>}
      {card.headline && <p className="mt-1 text-zinc-800 dark:text-zinc-200">{card.headline}</p>}
      {card.place && <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">{card.place}</p>}
      {card.therapies.length > 0 && (
        <p className="mt-2 text-sm text-zinc-800 dark:text-zinc-200">
          <span className="font-medium">Terapias:</span> {card.therapies.join(", ")}
        </p>
      )}
      <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">
        {[
          joinWithY(card.serviceModes.map(labelServiceMode)),
          joinWithY(card.sessionFormats.map(labelSessionFormat)),
          card.languages.length > 0 ? `Idiomas: ${card.languages.map(labelLanguage).join(", ")}` : "",
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      <div className="mt-2">
        <RatesLine card={card} />
      </div>
      <p className="mt-3">
        <Link
          className="inline-block rounded-md border border-zinc-900 px-3 py-1.5 text-sm font-medium text-zinc-900 hover:bg-zinc-100 dark:border-zinc-100 dark:text-zinc-100 dark:hover:bg-zinc-800"
          href={`/terapeuta/${card.profileId}`}
          aria-label={`Ver perfil de ${card.displayName}`}
        >
          Ver perfil
        </Link>
      </p>
    </article>
  );
}
