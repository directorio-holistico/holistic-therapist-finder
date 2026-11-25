// All therapists at a glance, one container per state. Read-only: nothing here changes what a therapist wrote.
// The phone number and the e-mail are NOT shown; the WhatsApp icon is the only way to reach the person from here.
// Todos los terapeutas de un vistazo, un contenedor por estado. Solo lectura: nada de acá cambia lo que escribió el terapeuta.
// El número de teléfono y el mail NO se muestran; el ícono de WhatsApp es la única forma de contactar a la persona desde acá.

import { Suspense } from "react";
import { SocialIcon } from "@/components/social-icon";
import { flagSrc } from "@/lib/card-view";
import { loadTherapistList } from "@/lib/admin/therapist-list";
import { groupByState, type RatesState, type TherapistRow } from "@/lib/admin/therapist-list-view";
import { requireAdmin } from "@/lib/admin/guard";
import { formatDate } from "@/lib/format";

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

async function List() {
  const { supabase } = await requireAdmin();
  const { rows, complete } = await loadTherapistList(supabase);
  const groups = groupByState(rows);
  return (
    <>
      {!complete && (
        <p role="status" className="mt-4 rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-aviso-texto">
          Se leyó solo una parte de los registros: la lista puede estar incompleta.
        </p>
      )}
      <p className="mt-2 text-apagado">Total: {rows.length}</p>
      {groups.length === 0 && <p className="mt-4 text-apagado">Todavía no hay terapeutas registrados.</p>}
      {groups.map((group) => (
        <details key={group.state} open className="mt-4 rounded-xl border border-linea bg-superficie">
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

export default function TherapistsPage() {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Terapeutas</h1>
      <p className="mt-2 text-apagado">
        Registro: cuándo se registró. Precios: la última vez que confirmó sus precios. El ícono abre WhatsApp si la persona lo marcó y cargó el número con el código de país.
      </p>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <List />
      </Suspense>
    </main>
  );
}
