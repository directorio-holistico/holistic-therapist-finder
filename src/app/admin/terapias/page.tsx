// Therapy catalog for the administrator: add a therapy, hide / show one, and see what therapists asked for. Read with the administrator's
// session; every change goes through a database function that checks the administrator again and leaves a trace.
// Catálogo de terapias para el administrador: agregar una, ocultar / mostrar una, y ver lo que pidieron los terapeutas. Se lee con la
// sesión del administrador; cada cambio pasa por una función de la base que vuelve a revisar al administrador y deja registro.

import Link from "next/link";
import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { loadSuggestions, loadTherapyCatalog } from "@/lib/admin/therapies";
import { RESULT_NOTICES, THERAPY_LIMITS, parseNameParam, revisionStatusLabel, splitSuggestedTherapies } from "@/lib/admin/therapy-admin";
import { formatDate } from "@/lib/format";
import { findExistingTherapy } from "@/lib/therapy-match";
import { AddTherapyForm, TherapyToggle } from "./therapy-forms";

type SearchParams = Promise<{ resultado?: string | string[]; nombre?: string | string[] }>;

const BOX = "rounded-xl border border-linea bg-superficie p-5";
const TITLE = "font-display text-xl font-semibold text-tinta";

async function Content({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireAdmin();
  const params = await searchParams;
  const result = typeof params.resultado === "string" ? params.resultado : undefined;
  const notice = result === undefined ? undefined : RESULT_NOTICES[result];
  const defaultName = parseNameParam(params.nombre);

  const [therapies, suggestions] = await Promise.all([loadTherapyCatalog(supabase), loadSuggestions(supabase)]);
  const options = therapies.map((therapy) => ({ id: therapy.id, name: therapy.name }));
  const hidden = therapies.filter((therapy) => !therapy.isActive).length;

  return (
    <>
      {notice && <p role="status" className="mt-4 rounded-lg border border-ok-borde bg-ok-fondo p-3 text-ok-texto">{notice}</p>}

      <div className="mt-6">
        <AddTherapyForm key={defaultName} defaultName={defaultName} />
      </div>

      <section aria-labelledby="sugeridas" className="mt-8">
        <h2 id="sugeridas" className={TITLE}>Terapias pedidas por terapeutas</h2>
        {suggestions.length === 0 ? (
          <p className="mt-2 text-apagado">Nadie pidió una terapia nueva.</p>
        ) : (
          <ul className="mt-3 grid gap-3">
            {suggestions.map((row) => (
              <li key={row.revisionId} className={BOX}>
                <p className="text-tinta">{row.profileName}</p>
                <p className="mt-1 text-sm text-apagado">{revisionStatusLabel(row.statusCode)} · {formatDate(row.at) ?? "—"}</p>
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

      <section aria-labelledby="catalogo" className="mt-8">
        <h2 id="catalogo" className={TITLE}>Terapias del catálogo</h2>
        <p className="mt-1 text-apagado">{therapies.length - hidden} visibles y {hidden} ocultas.</p>
        <ul className="mt-3 grid gap-3">
          {therapies.map((therapy) => (
            <li key={therapy.id} className={`${BOX} flex flex-wrap items-center justify-between gap-4`}>
              <div className="min-w-0">
                <p className="font-medium text-tinta">{therapy.name}</p>
                <p className="mt-1 text-sm text-apagado">
                  {therapy.isActive ? "Visible" : "Oculta"} · código {therapy.code}
                  {therapy.shortName ? ` · corto «${therapy.shortName}»` : ""}
                  {` · ${therapy.profiles} ${therapy.profiles === 1 ? "perfil" : "perfiles"}`}
                </p>
              </div>
              <TherapyToggle therapyId={therapy.id} name={therapy.name} isActive={therapy.isActive} profiles={therapy.profiles} />
            </li>
          ))}
        </ul>
      </section>
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
