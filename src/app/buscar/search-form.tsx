// The search form is a plain GET form: it works without JavaScript and the result has its own shareable address.
// El formulario es un GET común: funciona sin JavaScript y el resultado tiene su propia dirección para compartir.

import type { CatalogOption } from "@/lib/catalogs";
import type { SearchQuery } from "@/lib/search-query";

const fieldClass =
  "w-full rounded-md border border-zinc-400 bg-white px-3 py-2 text-base text-zinc-900 dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-100";
const labelClass = "mb-1 block text-sm font-medium text-zinc-800 dark:text-zinc-200";

type Props = {
  therapies: CatalogOption[];
  countries: CatalogOption[];
  regions: CatalogOption[];
  query: SearchQuery;
};

export function SearchForm({ therapies, countries, regions, query }: Props) {
  return (
    <form action="/buscar" method="get" className="grid gap-4">
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
        <div>
          <label htmlFor="region" className={labelClass}>Región (opcional)</label>
          <select id="region" name="region" defaultValue={query.regionId ?? ""} className={fieldClass}>
            <option value="">Todo el país</option>
            {regions.map((option) => (
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
    </form>
  );
}
