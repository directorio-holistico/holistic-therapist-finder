// All therapists at a glance, one container per state. Read-only: nothing here changes what a therapist wrote.
// The phone number is NOT shown; the WhatsApp icon is the way to reach the person. The e-mail shows only for "unpublished" (nothing else to reach them by).
// Todos los terapeutas de un vistazo, un contenedor por estado. Solo lectura: nada de acá cambia lo que escribió el terapeuta.
// El número de teléfono NO se muestra; el ícono de WhatsApp es la forma de contactar. El mail solo se ve en "unpublished" (no hay otra forma).

import { Suspense } from "react";
import { SocialIcon } from "@/components/social-icon";
import { flagSrc } from "@/lib/card-view";
import { loadTherapistList } from "@/lib/admin/therapist-list";
import { countryOptions, filterRows, groupByState, isFiltering, nudgeGmailLink, parseListFilter, type ListFilter, type RatesState, type TherapistRow } from "@/lib/admin/therapist-list-view";
import { requireAdmin } from "@/lib/admin/guard";
import { formatDate } from "@/lib/format";
import { SITE_URL } from "@/lib/site";

const FOCUS = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";
const RATES_LABEL: Record<RatesState, string> = { current: "al día", expired: "vencidos", none: "sin cargar" };

function Flag({ row }: { row: TherapistRow }) {
  const src = flagSrc(row.countryIso);
  if (!src) return <span className="inline-flex h-6 w-8 shrink-0 items-center justify-center text-apagado" title="Sin país">—<span className="sr-only">Sin país</span></span>;
  return (
    // Plain <img>: a small static SVG from /public. / <img> simple: un SVG chico y estático de /public.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={row.countryName ?? ""} title={row.countryName ?? undefined} width={32} height={24} loading="lazy" decoding="async" className="h-6 w-8 shrink-0 rounded-sm object-cover ring-1 ring-linea" />
  );
}

function Row({ row }: { row: TherapistRow }) {
  const registered = formatDate(row.registeredAt) ?? "—";
  const prices = formatDate(row.ratesConfirmedAt);
  return (
    <li className="flex items-center gap-3 px-4 py-3">
      <Flag row={row} />
      <div className="min-w-0 flex-1">
        <p className="break-words font-medium text-tinta">{row.name}</p>
        <p className="text-sm text-apagado">
          Registro: {registered} · Precios: {prices ? `${prices} (${RATES_LABEL[row.rates]})` : RATES_LABEL[row.rates]}
        </p>
        {row.note && <p className="text-sm text-aviso-texto">{row.note}</p>}
        {row.email && (
          <p className="break-all text-sm text-tinta">
            {row.email}
            {" · "}
            <a href={nudgeGmailLink(row.email, SITE_URL) ?? undefined} target="_blank" rel="noopener noreferrer" className={`text-acento underline underline-offset-4 ${FOCUS}`}>
              Escribirle
            </a>
          </p>
        )}
      </div>
      {row.whatsappLink ? (
        <a
          href={row.whatsappLink}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={`Abrir WhatsApp con ${row.name}`}
          className={`inline-flex size-11 shrink-0 items-center justify-center rounded-full border border-linea text-tinta hover:bg-fondo ${FOCUS}`}
        >
          <SocialIcon kind="whatsapp" size={22} />
        </a>
      ) : (
        <span className="inline-flex min-h-11 shrink-0 items-center text-xs text-apagado">{row.hasPhone ? "Sin WhatsApp" : "Sin teléfono"}</span>
      )}
    </li>
  );
}

type SearchParams = Promise<{ q?: string | string[]; pais?: string | string[] }>;

// Plain GET form: the filter lives in the address, so it can be shared and survives a reload. / Formulario GET simple: el filtro vive en la dirección.
function FilterForm({ filter, countries }: { filter: ListFilter; countries: { iso: string; name: string }[] }) {
  return (
    <form method="get" className="mt-4 flex flex-wrap items-end gap-3">
      <div className="flex flex-col gap-1">
        <label htmlFor="q" className="text-sm text-apagado">Nombre</label>
        <input id="q" name="q" type="search" defaultValue={filter.q} maxLength={80} className={`min-h-11 rounded-lg border border-linea bg-superficie px-3 text-tinta ${FOCUS}`} />
      </div>
      <div className="flex flex-col gap-1">
        <label htmlFor="pais" className="text-sm text-apagado">País</label>
        <select id="pais" name="pais" defaultValue={filter.country} className={`min-h-11 rounded-lg border border-linea bg-superficie px-3 text-tinta ${FOCUS}`}>
          <option value="">Todos</option>
          {countries.map((country) => (
            <option key={country.iso} value={country.iso}>{country.name}</option>
          ))}
        </select>
      </div>
      <button type="submit" className={`min-h-11 rounded-lg bg-acento px-4 font-medium text-white ${FOCUS}`}>Filtrar</button>
      {isFiltering(filter) && (
        <a href="/admin/terapeutas" className={`inline-flex min-h-11 items-center text-acento underline underline-offset-4 ${FOCUS}`}>Quitar filtro</a>
      )}
    </form>
  );
}

async function List({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireAdmin();
  const filter = parseListFilter(await searchParams);
  const { rows: all, complete } = await loadTherapistList(supabase);
  const filtering = isFiltering(filter);
  const rows = filterRows(all, filter);
  const groups = groupByState(rows);
  return (
    <>
      <FilterForm filter={filter} countries={countryOptions(all)} />
      {!complete && (
        <p role="status" className="mt-4 rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-aviso-texto">
          Se leyó solo una parte de los registros: la lista puede estar incompleta.
        </p>
      )}
      <p className="mt-2 text-apagado">{filtering ? `Resultados: ${rows.length} de ${all.length}` : `Total: ${all.length}`}</p>
      {groups.length === 0 && <p className="mt-4 text-apagado">{filtering ? "Ningún terapeuta coincide con el filtro." : "Todavía no hay terapeutas registrados."}</p>}
      {groups.map((group) => (
        <details key={group.state} open={filtering} className="mt-4 rounded-xl border border-linea bg-superficie">
          <summary className={`flex min-h-11 cursor-pointer items-center px-4 py-2 font-display text-xl font-semibold text-tinta ${FOCUS}`}>
            {group.title} <span className="ml-2 text-apagado">({group.rows.length})</span>
          </summary>
          <ul className="divide-y divide-linea border-t border-linea">
            {group.rows.map((row) => (
              <Row key={row.profileId} row={row} />
            ))}
          </ul>
        </details>
      ))}
    </>
  );
}

export default function TherapistsPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Terapeutas</h1>
      <p className="mt-2 text-apagado">
        Registro: cuándo se registró. Precios: la última vez que confirmó sus precios. El ícono abre WhatsApp si la persona lo marcó y cargó el número con el código de país. El mail solo se muestra de quien se registró y nunca guardó nada. Publicados: del más reciente al más antiguo según su primera publicación.
      </p>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <List searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
