// Search page. The static shell (title, legal notice) is prerendered; everything that depends on the URL or the database
// is inside Suspense and runs per request (Next.js 16 with Cache Components).
// Página de búsqueda. El armazón estático (título, aviso legal) se prerenderiza; lo que depende de la URL o de la base
// va dentro de Suspense y corre por pedido (Next.js 16 con Cache Components).

import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { getLocationOptions, getTherapies } from "@/lib/catalog-cache";
import { SEARCH_GROUP_TITLES } from "@/lib/labels";
import { logUnmetSearch, searchProfiles, splitByGroup } from "@/lib/search";
import { PAGE_SIZE, buildSearchHref, locationIdOf, parseSearchQuery } from "@/lib/search-query";
import { createAnonClient } from "@/lib/supabase/anon-client";
import { ProfileCard } from "./profile-card";
import { SearchForm } from "./search-form";

export const metadata: Metadata = {
  title: "Buscar terapeutas",
  description: "Elegí una terapia y una zona para ver terapeutas holísticos y cómo contactarlos.",
};

type RawParams = Promise<Record<string, string | string[] | undefined>>;

export default function SearchPage({ searchParams }: { searchParams: RawParams }) {
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-8">
      <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">Buscar terapeutas</h1>
      <Suspense fallback={<p className="mt-4 text-zinc-700 dark:text-zinc-300">Cargando la búsqueda…</p>}>
        <SearchContent searchParams={searchParams} />
      </Suspense>
      <p className="mt-10 border-t border-zinc-300 pt-4 text-sm text-zinc-700 dark:border-zinc-700 dark:text-zinc-300">
        Este sitio solo conecta personas con terapeutas: no da turnos ni cobra, y no reemplaza la atención médica ni
        psicológica. Desconfiá de quien prometa curas.
      </p>
    </main>
  );
}

async function SearchContent({ searchParams }: { searchParams: RawParams }) {
  const parsed = parseSearchQuery(await searchParams);

  const [therapies, countries] = await Promise.all([getTherapies(), getLocationOptions(null)]);
  const regions = parsed.countryId !== null ? await getLocationOptions(parsed.countryId) : [];

  // Keep only choices that exist; a region that does not belong to the chosen country is dropped.
  // Se conservan solo opciones que existen; una región que no es del país elegido se descarta.
  const query = {
    ...parsed,
    therapyId: therapies.some((option) => option.id === parsed.therapyId) ? parsed.therapyId : null,
    countryId: countries.some((option) => option.id === parsed.countryId) ? parsed.countryId : null,
    regionId: regions.some((option) => option.id === parsed.regionId) ? parsed.regionId : null,
  };
  const locationId = locationIdOf(query);

  return (
    <>
      <div className="mt-4">
        <SearchForm therapies={therapies} countries={countries} regions={regions} query={query} />
      </div>
      {query.therapyId !== null && locationId !== null ? (
        <Results query={query} therapyId={query.therapyId} locationId={locationId} therapyName={therapies.find((o) => o.id === query.therapyId)?.name ?? ""} />
      ) : null}
    </>
  );
}

type ResultsProps = {
  query: ReturnType<typeof parseSearchQuery>;
  therapyId: number;
  locationId: number;
  therapyName: string;
};

async function Results({ query, therapyId, locationId, therapyName }: ResultsProps) {
  const client = createAnonClient();
  const { cards, total } = await searchProfiles(client, {
    therapyId,
    locationId,
    serviceMode: query.serviceMode,
    page: query.page,
  });

  if (cards.length === 0) {
    // Only the first page of a search that returns nothing is unmet demand; the database re-checks it.
    // Solo la primera página de una búsqueda sin nada es demanda no cubierta; la base lo vuelve a comprobar.
    if (query.page === 1) {
      await logUnmetSearch(client, { therapyId, locationId, serviceMode: query.serviceMode });
      return (
        <section aria-labelledby="results-title" className="mt-8">
          <h2 id="results-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">Sin resultados</h2>
          <p className="mt-2 text-zinc-800 dark:text-zinc-200">
            Todavía no hay terapeutas de {therapyName} para esa zona. Anotamos tu búsqueda, sin datos personales, para saber
            dónde hace falta. Podés probar con todo el país o con atención a distancia.
          </p>
        </section>
      );
    }
    return (
      <section aria-labelledby="results-title" className="mt-8">
        <h2 id="results-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">No hay más resultados</h2>
        <p className="mt-2">
          <Link className="underline" href={buildSearchHref(query, 1)}>Volver a la primera página</Link>
        </p>
      </section>
    );
  }

  const lastPage = Math.max(1, Math.ceil(total / PAGE_SIZE));
  return (
    <section aria-labelledby="results-title" className="mt-8">
      <h2 id="results-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">
        {total === 1 ? "1 terapeuta" : `${total} terapeutas`}
      </h2>
      {splitByGroup(cards).map((group) => (
        <div key={group.group} className="mt-6">
          <h3 className="mb-3 text-base font-semibold text-zinc-800 dark:text-zinc-200">{SEARCH_GROUP_TITLES[group.group] ?? ""}</h3>
          <div className="grid gap-4">
            {group.cards.map((card) => (
              <ProfileCard key={card.profileId} card={card} />
            ))}
          </div>
        </div>
      ))}
      {lastPage > 1 && (
        <nav aria-label="Páginas de resultados" className="mt-8 flex items-center justify-between text-zinc-900 dark:text-zinc-100">
          {query.page > 1 ? (
            <Link className="underline" href={buildSearchHref(query, query.page - 1)}>Anterior</Link>
          ) : (
            <span />
          )}
          <span className="text-sm">Página {query.page} de {lastPage}</span>
          {query.page < lastPage ? (
            <Link className="underline" href={buildSearchHref(query, query.page + 1)}>Siguiente</Link>
          ) : (
            <span />
          )}
        </nav>
      )}
    </section>
  );
}
