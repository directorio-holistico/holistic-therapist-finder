"use client";

// The search form is a plain GET form: it works without JavaScript and the result has its own shareable address.
// With JavaScript it also updates the search by itself when a filter changes (after a short pause, so moving through the
// options with the keyboard does not fire a search for each one). The button stays for everyone else.
// El formulario es un GET común: funciona sin JavaScript y el resultado tiene su propia dirección para compartir.
// Con JavaScript además actualiza la búsqueda solo cuando cambia un filtro (con una pausa corta, para que recorrer las
// opciones con el teclado no dispare una búsqueda por cada una). El botón queda para el resto.

import { useRouter } from "next/navigation";
import { useEffect, useRef, useTransition, type FormEvent } from "react";
import type { CatalogOption } from "@/lib/catalogs";
import { hrefFromFormValues, type SearchQuery } from "@/lib/search-query";

const fieldClass =
  "w-full rounded-md border border-zinc-400 bg-white px-3 py-2 text-base text-zinc-900 dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-100";
const labelClass = "mb-1 block text-sm font-medium text-zinc-800 dark:text-zinc-200";
const PAUSE_MS = 400;

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

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  function onChange(event: FormEvent<HTMLFormElement>) {
    const form = event.currentTarget;
    const changed = (event.target as HTMLSelectElement).name;
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      const href = hrefFromFormValues(new FormData(form).entries(), changed);
      startTransition(() => router.push(href, { scroll: false }));
    }, PAUSE_MS);
  }

  return (
    <form action="/buscar" method="get" className="grid gap-4" onChange={onChange} aria-busy={pending}>
      <div>
        <label htmlFor="therapy" className={labelClass}>Terapia</label>
        <select id="therapy" name="therapy" defaultValue={query.therapyId ?? ""} className={fieldClass}>
          <option value="">Todas las terapias</option>
          {therapies.map((option) => (
            <option key={option.id} value={option.id}>{option.name}</option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="country" className={labelClass}>País</label>
        <select id="country" name="country" defaultValue={query.countryId ?? ""} className={fieldClass}>
          <option value="">Todos los países</option>
          {countries.map((option) => (
            <option key={option.id} value={option.id}>{option.name}</option>
          ))}
        </select>
      </div>

      {regions.length > 0 && (
        <div key={`region-${query.countryId}`}>
          <label htmlFor="region" className={labelClass}>Región (opcional)</label>
          <select id="region" name="region" defaultValue={query.regionId ?? ""} className={fieldClass}>
            <option value="">Todo el país</option>
            {regions.map((option) => (
              <option key={option.id} value={option.id}>{option.name}</option>
            ))}
          </select>
        </div>
      )}

      {cities.length > 0 && (
        <div key={`city-${query.regionId}`}>
          <label htmlFor="city" className={labelClass}>Ciudad (opcional)</label>
          <select id="city" name="city" defaultValue={query.cityId ?? ""} className={fieldClass}>
            <option value="">Toda la región</option>
            {cities.map((option) => (
              <option key={option.id} value={option.id}>{option.name}</option>
            ))}
          </select>
        </div>
      )}

      <div>
        <label htmlFor="mode" className={labelClass}>Modo de atención</label>
        <select id="mode" name="mode" defaultValue={query.serviceMode ?? ""} className={fieldClass}>
          <option value="">Presencial o a distancia</option>
          <option value="in_person">Presencial</option>
          <option value="remote">A distancia</option>
        </select>
      </div>

      <button
        type="submit"
        className="rounded-md bg-zinc-900 px-4 py-2 text-base font-medium text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
      >
        Buscar
      </button>
      <p className="text-sm text-zinc-700 dark:text-zinc-300" role="status">
        {pending ? "Actualizando resultados…" : "Los resultados se actualizan al cambiar un filtro."}
      </p>
    </form>
  );
}
