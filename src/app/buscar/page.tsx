// Search page. The static shell (title, health notice) is prerendered; everything that depends on the URL or the database
// is inside Suspense and runs per request (Next.js 16 with Cache Components).
// Página de búsqueda. El armazón estático (título, aviso legal) se prerenderiza; lo que depende de la URL o de la base
// va dentro de Suspense y corre por pedido (Next.js 16 con Cache Components).

import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { getLocationOptions, getTherapies } from "@/lib/catalog-cache";
import { groupHeading, searchGroupTitle, terapeutasCount } from "@/lib/labels";
import { recordUnmetSearch } from "@/lib/rate-limit-server";
import { searchProfiles, splitByGroup } from "@/lib/search";
import { PAGE_SIZE, buildSearchHref, locationIdOf, parseSearchQuery } from "@/lib/search-query";
import { HealthNotice } from "@/components/health-notice";import { SiteHeader } from "@/components/site-header";
import { createAnonClient } from "@/lib/supabase/anon-client";
import { ProfileCard } from "./profile-card";
import { SearchForm } from "./search-form";

export const metadata: Metadata = {
  title: "Buscar terapeutas",
  description: "Mirá todos los terapeutas holísticos o filtrá por terapia, zona y modo de atención.",
};

type RawParams = Promise<Record<string, string | string[] | undefined>>;

export default function SearchPage({ searchParams }: { searchParams: RawParams }) {
  return (
    <>
    <SiteHeader />
    <main className="mx-auto w-full max-w-4xl px-4 py-8">
      <h1 className="font-display text-4xl font-semibold text-tinta">Buscar terapeutas</h1>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando la búsqueda…</p>}>
        <SearchContent searchParams={searchParams} />
      </Suspense>
      <HealthNotice className="mt-10" />
    </main>
    </>
  );
}

async function SearchContent({ searchParams }: { searchParams: RawParams }) {
  const parsed = parseSearchQuery(await searchParams);

  const [therapies, countries] = await Promise.all([getTherapies(), getLocationOptions(null)]);
  const regions = parsed.countryId !== null ? await getLocationOptions(parsed.countryId) : [];
  // Cities hang under a region, so the city list only exists once a region is chosen.
  // Las ciudades cuelgan de una región, así que la lista de ciudades existe recién con una región elegida.
  const cities = parsed.regionId !== null && regions.some((option) => option.id === parsed.regionId) ? await getLocationOptions(parsed.regionId) : [];

  // Keep only choices that exist; a region that does not belong to the chosen country (or a city to the region) is dropped.
  // Se conservan solo opciones que existen; una región que no es del país elegido (o una ciudad de la región) se descarta.
  const query = {
    ...parsed,
    therapyId: therapies.some((option) => option.id === parsed.therapyId) ? parsed.therapyId : null,
    countryId: countries.some((option) => option.id === parsed.countryId) ? parsed.countryId : null,
    regionId: regions.some((option) => option.id === parsed.regionId) ? parsed.regionId : null,
    cityId: cities.some((option) => option.id === parsed.cityId) ? parsed.cityId : null,
  };
  const locationId = locationIdOf(query);

  return (
    <>
      <div className="mt-4">
        <SearchForm therapies={therapies} countries={countries} regions={regions} cities={cities} query={query} />
      </div>
      <Results query={query} therapyId={query.therapyId} locationId={locationId} therapyName={therapies.find((o) => o.id === query.therapyId)?.name ?? ""} />
    </>
  );
}

type ResultsProps = {
  query: ReturnType<typeof parseSearchQuery>;
  therapyId: number | null;
  locationId: number | null;
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
      // Only a search with a specific therapy and place is unmet demand; with "Todos" there is nothing specific to count.
      // Solo una búsqueda con terapia y lugar concretos es demanda no cubierta; con "Todos" no hay nada concreto que contar.
      if (therapyId !== null && locationId !== null) {
        await recordUnmetSearch({ therapyId, locationId, serviceMode: query.serviceMode });
        return (
          <section aria-labelledby="results-title" className="mt-8">
            <h2 id="results-title" className="font-display text-2xl font-semibold text-tinta">Sin resultados</h2>
            <p className="mt-2 text-tinta">
              Todavía no hay terapeutas de {therapyName} para esa zona. Anotamos tu búsqueda, sin datos personales, para saber
              dónde hace falta. Podés probar con todo el país, con atención a distancia o con «Todos» en terapia o país.
            </p>
          </section>
        );
      }
      return (
        <section aria-labelledby="results-title" className="mt-8">
          <h2 id="results-title" className="font-display text-2xl font-semibold text-tinta">Sin resultados</h2>
          <p className="mt-2 text-tinta">
            Todavía no hay terapeutas con esos filtros. Probá con otra terapia, otro país o sin elegir el modo de atención.
          </p>
        </section>
      );
    }
    return (
      <section aria-labelledby="results-title" className="mt-8">
        <h2 id="results-title" className="font-display text-2xl font-semibold text-tinta">No hay más resultados</h2>
        <p className="mt-2">
          <Link className="underline" href={buildSearchHref(query, 1)}>Volver a la primera página</Link>
        </p>
      </section>
    );
  }

  const lastPage = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const singlePage = lastPage === 1;
  const zoneChosen = query.regionId !== null || query.cityId !== null;
  return (
    <section aria-labelledby="results-title" className="mt-8">
      {/* One page: every group shows ITS OWN count and the total is not repeated (it was confusing: "2" above, "1" below).
          Several pages: a group may continue on the next page, so the heading shows the grand total instead.
          Una página: cada grupo muestra SU cantidad y no se repite el total (confundía: "2" arriba, "1" abajo).
          Varias páginas: un grupo puede seguir en la siguiente, así que el título muestra el total general. */}
      <h2 id="results-title" className={singlePage ? "sr-only" : "font-display text-2xl font-semibold text-tinta"}>
        {singlePage ? "Resultados de la búsqueda" : terapeutasCount(total)}
      </h2>
      {splitByGroup(cards).map((group) => (
        <div key={group.group} className="mt-6">
          <h3 className="mb-3 text-base font-semibold text-tinta">
            {singlePage ? groupHeading(searchGroupTitle(group.group, zoneChosen), group.cards.length) : searchGroupTitle(group.group, zoneChosen)}
          </h3>
          <div className="grid gap-4 sm:grid-cols-2">
            {group.cards.map((card) => (
              <ProfileCard key={card.profileId} card={card} />
            ))}
          </div>
        </div>
      ))}
      {lastPage > 1 && (
        <nav aria-label="Páginas de resultados" className="mt-8 flex items-center justify-between text-tinta">
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
