"use client";

// The search form is a plain GET form: it works without JavaScript and the result has its own shareable address.
// With JavaScript it also updates the search by itself when a filter changes (after a short pause, so moving through the
// options with the keyboard does not fire a search for each one). The button stays for everyone else.
// El formulario es un GET común: funciona sin JavaScript y el resultado tiene su propia dirección para compartir.
// Con JavaScript además actualiza la búsqueda solo cuando cambia un filtro (con una pausa corta, para que recorrer las
// opciones con el teclado no dispare una búsqueda por cada una). El botón queda para el resto.

import { useRouter } from "next/navigation";
import { useEffect, useRef, useTransition, type FormEvent, type MouseEvent } from "react";
import { ModeBadge } from "@/components/mode-icon";
import { SearchableSelect } from "@/components/searchable-select";
import type { CatalogOption } from "@/lib/catalogs";
import { hrefFromFormValues, type SearchQuery } from "@/lib/search-query";

const fieldClass =
  "min-h-11 w-full appearance-none rounded-xl border border-campo bg-superficie py-2 pl-3 pr-9 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";

// Same arrow as the searchable "Terapia" field, so the three filters look alike. / La misma flecha del campo "Terapia", así los tres filtros se ven iguales.
function Chevron() {
  return <span aria-hidden="true" className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm text-apagado">▾</span>;
}
const labelClass = "mb-1 block text-sm font-semibold text-tinta";
const PAUSE_MS = 400;
const MODES = ["in_person", "remote"] as const;

type Props = {
  therapies: CatalogOption[];
  countries: CatalogOption[];
  regions: CatalogOption[];
  cities: CatalogOption[];
  query: SearchQuery;
};

export function SearchForm({ therapies, countries, regions, cities, query }: Props) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  // Waits a short pause and searches with the current values of the form. / Espera una pausa corta y busca con los valores actuales del formulario.
  function schedule(form: HTMLFormElement, changed: string) {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      const href = hrefFromFormValues(new FormData(form).entries(), changed);
      startTransition(() => router.push(href, { scroll: false }));
    }, PAUSE_MS);
  }

  function onChange(event: FormEvent<HTMLFormElement>) {
    schedule(event.currentTarget, (event.target as HTMLSelectElement).name);
  }

  // Unchecking the last checked box is refused (the click is cancelled, so no change and no search happens). / Destildar la última casilla tildada se rechaza (se cancela el clic, no hay cambio ni búsqueda).
  function keepOneChecked(event: MouseEvent<HTMLInputElement>) {
    const form = event.currentTarget.form;
    if (!form) return;
    if (form.querySelectorAll('input[name="mode"]:checked').length === 0) event.preventDefault();
  }

  return (
    <form ref={formRef} action="/buscar" method="get" className="grid grid-cols-1 gap-x-3 gap-y-4 rounded-2xl border border-linea bg-superficie p-5 shadow-sm sm:grid-cols-3" onChange={onChange} aria-busy={pending}>
      <div>
        <label htmlFor="therapy" className={labelClass}>Terapia</label>
        <SearchableSelect id="therapy" name="therapy" options={therapies} emptyLabel="Todas las terapias" listLabel="Terapias"
          defaultValue={String(query.therapyId ?? "")} variant="site"
          onSelect={() => { if (formRef.current) schedule(formRef.current, "therapy"); }} />
      </div>

      <div>
        <label htmlFor="country" className={labelClass}>País</label>
        <div className="relative">
          <select id="country" name="country" defaultValue={query.countryId ?? ""} className={fieldClass}>
            <option value="">Todos los países</option>
            {countries.map((option) => (
              <option key={option.id} value={option.id}>{option.name}</option>
            ))}
          </select>
          <Chevron />
        </div>
      </div>

      {regions.length > 0 && (
        <div key={`region-${query.countryId}`}>
          <label htmlFor="region" className={labelClass}>Región (opcional)</label>
          <div className="relative">
            <select id="region" name="region" defaultValue={query.regionId ?? ""} className={fieldClass}>
              <option value="">Todo el país</option>
              {regions.map((option) => (
                <option key={option.id} value={option.id}>{option.name}</option>
              ))}
            </select>
            <Chevron />
          </div>
        </div>
      )}

      {cities.length > 0 && (
        <div key={`city-${query.regionId}`}>
          <label htmlFor="city" className={labelClass}>Ciudad (opcional)</label>
          <div className="relative">
            <select id="city" name="city" defaultValue={query.cityId ?? ""} className={fieldClass}>
              <option value="">Toda la región</option>
              {cities.map((option) => (
                <option key={option.id} value={option.id}>{option.name}</option>
              ))}
            </select>
            <Chevron />
          </div>
        </div>
      )}

      {/* Two checkboxes, both checked by default (no filter). One must always stay checked. / Dos casillas, las dos tildadas por defecto (sin filtro). Siempre debe quedar una tildada. */}
      <fieldset className="col-span-full" aria-describedby="mode-hint">
        <legend className={labelClass}>Modo de atención</legend>
        <div className="flex flex-wrap gap-x-6 gap-y-1">
          {MODES.map((mode) => (
            <label key={mode} className="inline-flex min-h-11 cursor-pointer items-center gap-3">
              <input
                type="checkbox"
                name="mode"
                value={mode}
                defaultChecked={query.serviceMode === null || query.serviceMode === mode}
                onClick={keepOneChecked}
                className="size-5 shrink-0 cursor-pointer accent-boton focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
              />
              <ModeBadge mode={mode} />
            </label>
          ))}
        </div>
        <p id="mode-hint" className="sr-only">Tiene que quedar al menos una opción marcada.</p>
      </fieldset>

      <button
        type="submit"
        className="col-span-full min-h-10 justify-self-center rounded-full bg-boton px-10 text-sm font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
      >
        Buscar
      </button>
      <p className="col-span-full text-sm text-apagado" role="status">
        {pending ? "Actualizando resultados…" : "Los resultados se actualizan al cambiar un filtro."}
      </p>
    </form>
  );
}
