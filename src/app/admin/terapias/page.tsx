// Therapy catalog for the administrator: add a therapy, hide / show one, and see what therapists asked for. Read with the administrator's
// session; every change goes through a database function that checks the administrator again and leaves a trace.
// Catálogo de terapias para el administrador: agregar una, ocultar / mostrar una, y ver lo que pidieron los terapeutas. Se lee con la
// sesión del administrador; cada cambio pasa por una función de la base que vuelve a revisar al administrador y deja registro.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { loadSuggestions, loadTherapyCatalog, type TherapyRow } from "@/lib/admin/therapies";
import {
  RESULT_NOTICES, THERAPY_LIMITS, canDismissSuggestion, parseNameParam, revisionStatusLabel, splitSuggestedTherapies,
} from "@/lib/admin/therapy-admin";
import { formatDate } from "@/lib/format";
import { findExistingTherapy } from "@/lib/therapy-match";
import { AddTherapyForm, DismissSuggestion, TherapyToggle } from "./therapy-forms";

type SearchParams = Promise<{ resultado?: string | string[]; nombre?: string | string[] }>;

const BOX = "rounded-xl border border-linea bg-superficie p-5";
const TITLE = "font-display text-xl font-semibold text-tinta";
const SUMMARY = "flex min-h-11 cursor-pointer items-center font-display text-xl font-semibold text-tinta focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";

function TherapyList({ rows }: { rows: TherapyRow[] }) {
  return (
    <ul className="mt-3 grid gap-3">
      {rows.map((therapy) => (
        <li key={therapy.id} className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-linea bg-fondo p-4">
          <div className="min-w-0">
            <p className="font-medium text-tinta">{therapy.name}</p>
            <p className="mt-1 text-sm text-apagado">
              Código {therapy.code}
              {therapy.shortName ? ` · corto «${therapy.shortName}»` : ""}
              {` · ${therapy.profiles} ${therapy.profiles === 1 ? "perfil" : "perfiles"}`}
            </p>
          </div>
          <TherapyToggle therapyId={therapy.id} name={therapy.name} isActive={therapy.isActive} profiles={therapy.profiles} />
        </li>
      ))}
    </ul>
  );
}

async function Content({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireAdmin();
  const params = await searchParams;
  const result = typeof params.resultado === "string" ? params.resultado : undefined;
  const notice = result === undefined ? undefined : RESULT_NOTICES[result];
  const defaultName = parseNameParam(params.nombre);

  const [therapies, suggestions] = await Promise.all([loadTherapyCatalog(supabase), loadSuggestions(supabase)]);
  const options = therapies.map((therapy) => ({ id: therapy.id, name: therapy.name }));
  const visible = therapies.filter((therapy) => therapy.isActive);
  const hidden = therapies.filter((therapy) => !therapy.isActive);

  return (
    <>
      {notice && <p role="status" className="mt-4 rounded-lg border border-ok-borde bg-ok-fondo p-3 text-ok-texto">{notice}</p>}

      {/* open only when a request's "Agregar esta terapia" link brought a name / abierto solo cuando lo trae el enlace "Agregar esta terapia" de un pedido */}
      <details id="nueva" open={defaultName !== ""} className={`mt-6 ${BOX}`}>
        <summary className={SUMMARY}>Agregar una terapia</summary>
        <AddTherapyForm key={defaultName} defaultName={defaultName} />
      </details>

      <section aria-labelledby="sugeridas" className="mt-8">
        <h2 id="sugeridas" className={TITLE}>Terapias pedidas por terapeutas</h2>
        {suggestions.length === 0 ? (
          <p className="mt-2 text-apagado">Nadie pidió una terapia nueva.</p>
        ) : (
          <ul className="mt-3 grid gap-3">
            {suggestions.map((row) => (
              <li key={row.revisionId} className={BOX}>
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0">
                    <p className="text-tinta">{row.profileName}</p>
                    <p className="mt-1 text-sm text-apagado">{revisionStatusLabel(row.statusCode)} · {formatDate(row.at) ?? "—"}</p>
                  </div>
                  {canDismissSuggestion(row.statusCode)
                    ? <DismissSuggestion revisionId={row.revisionId} />
                    : <p className="max-w-56 text-sm text-apagado">Se puede descartar cuando la revisión esté decidida.</p>}
                </div>
                <ul className="mt-3 grid gap-2">
                  {splitSuggestedTherapies(row.text).map((name) => {
                    const existing = findExistingTherapy(options, name);
                    return (
                      <li key={name} className="flex flex-wrap items-center gap-x-4 gap-y-1">
                        <span className="font-medium text-tinta">{name}</span>
                        {existing ? (
                          <span className="text-sm text-apagado">Ya está en la lista como «{existing.name}».</span>
                        ) : (
                          <Link href={`/admin/terapias?nombre=${encodeURIComponent(name.slice(0, THERAPY_LIMITS.name))}#nueva`}
                            className="inline-flex min-h-11 items-center text-acento underline underline-offset-4">
                            Agregar esta terapia
                          </Link>
                        )}
                      </li>
                    );
                  })}
                </ul>
              </li>
            ))}
          </ul>
        )}
      </section>

      <details className={`mt-8 ${BOX}`}>
        <summary className={SUMMARY}>Terapias visibles ({visible.length})</summary>
        <TherapyList rows={visible} />
      </details>

      <details className={`mt-4 ${BOX}`}>
        <summary className={SUMMARY}>Terapias ocultas ({hidden.length})</summary>
        {hidden.length === 0 ? <p className="mt-3 text-apagado">No hay terapias ocultas.</p> : <TherapyList rows={hidden} />}
      </details>
    </>
  );
}

export default function TherapiesPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Terapias</h1>
      <p className="mt-2 text-apagado">Ocultar una terapia no la borra: los perfiles la conservan y los visitantes dejan de verla.</p>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <Content searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
