"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import type { ChildOption, CatalogOption, FormCatalogs } from "@/lib/catalogs";
import { labelLanguage, labelRateAudience, labelServiceMode, labelSessionFormat } from "@/lib/labels";
import type { FormDefaults } from "@/lib/profile-form";
import { saveProfile, type EditState } from "./actions";

const INITIAL: EditState = { status: "idle", message: "", fields: [], flagged: [] };
const FIELD = "w-full rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";
const LABEL = "font-medium text-zinc-900 dark:text-zinc-100";
const HELP = "text-sm text-zinc-600 dark:text-zinc-400";

type Props = {
  defaults: FormDefaults;
  catalogs: FormCatalogs;
  countries: CatalogOption[];
  regions: ChildOption[];
  cities: ChildOption[];
  initialCountryId: number | null;
  initialRegionId: number | null;
  missingCity: { regionId: number; cityName: string } | null;
  lastRejection: string | null;
};

function CheckGroup({ legend, name, options, selected, label }: {
  legend: string; name: string; options: { id: number; code: string }[]; selected: number[]; label: (code: string) => string;
}) {
  return (
    <fieldset className="grid gap-2">
      <legend className={LABEL}>{legend}</legend>
      {options.map((option) => (
        <label key={option.id} className="flex items-center gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name={name} value={option.id} defaultChecked={selected.includes(option.id)} className="h-5 w-5" />
          {label(option.code)}
        </label>
      ))}
    </fieldset>
  );
}

export function ProfileForm({ defaults, catalogs, countries, regions, cities, initialCountryId, initialRegionId, missingCity, lastRejection }: Props) {
  const [state, action, pending] = useActionState(saveProfile, INITIAL);
  const [countryId, setCountryId] = useState<number | null>(initialCountryId);
  const [regionId, setRegionId] = useState<number | null>(initialRegionId);
  const [cityMissing, setCityMissing] = useState<boolean>(missingCity !== null);
  const regionOptions = regions.filter((region) => region.parentId === countryId);
  const cityOptions = cities.filter((city) => city.parentId === regionId);
  const invalid = (field: string) => state.status === "error" && state.fields.includes(field);

  if (state.status === "submitted") {
    return (
      <section className="mt-6 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700" role="status">
        <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">{state.message}</h2>
        <p className="mt-1 text-zinc-700 dark:text-zinc-300">Te avisamos cuando esté revisado. Mientras tanto no podés cambiarlo.</p>
        {state.flagged.length > 0 && (
          <p className="mt-2 text-zinc-700 dark:text-zinc-300">
            Ojo: encontramos palabras que suelen rechazarse ({state.flagged.join(", ")}). No promete cura ni trata enfermedades: si querés, corregilas y volvé a enviar cuando te respondamos.
          </p>
        )}
        <Link href="/mi-perfil" className="mt-3 inline-block underline">Volver a mi perfil</Link>
      </section>
    );
  }

  return (
    <form action={action} className="mt-6 grid gap-6" noValidate>
      {lastRejection && (
        <p role="note" className="rounded-md border border-amber-400 bg-amber-50 p-3 text-sm text-amber-900">
          Tu última revisión fue rechazada: {lastRejection}
        </p>
      )}

      <section className="grid gap-4" aria-labelledby="sec-datos">
        <h2 id="sec-datos" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Tus datos</h2>
        <div className="grid gap-1">
          <label htmlFor="displayName" className={LABEL}>Nombre que se muestra</label>
          <input id="displayName" name="displayName" type="text" required maxLength={80} defaultValue={defaults.displayName}
            aria-invalid={invalid("displayName")} className={FIELD} />
        </div>
        <div className="grid gap-1">
          <label htmlFor="headline" className={LABEL}>Frase de presentación (opcional)</label>
          <textarea id="headline" name="headline" rows={3} maxLength={280} defaultValue={defaults.headline}
            aria-describedby="headline-help" aria-invalid={invalid("headline")} className={FIELD} />
          <p id="headline-help" className={HELP}>Hasta 280 caracteres. No prometas curas ni hables de enfermedades.</p>
        </div>
        <div className="grid gap-1">
          <label htmlFor="practiceStartYear" className={LABEL}>Año en que empezaste a atender (opcional)</label>
          <input id="practiceStartYear" name="practiceStartYear" type="number" inputMode="numeric" min={1900} max={2100}
            defaultValue={defaults.practiceStartYear} aria-invalid={invalid("practiceStartYear")} className={FIELD} />
        </div>
      </section>

      <section className="grid gap-4" aria-labelledby="sec-lugar">
        <h2 id="sec-lugar" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Dónde atendés</h2>
        <div className="grid gap-1">
          <label htmlFor="countryId" className={LABEL}>País</label>
          <select id="countryId" value={countryId ?? ""} className={FIELD}
            onChange={(event) => { setCountryId(event.target.value ? Number(event.target.value) : null); setRegionId(null); }}>
            <option value="">Elegí un país</option>
            {countries.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
          </select>
        </div>
        <div className="grid gap-1">
          <label htmlFor="regionId" className={LABEL}>Región</label>
          <select id="regionId" name="regionId" value={regionId ?? ""} disabled={countryId === null} aria-invalid={invalid("regionId")} className={FIELD}
            onChange={(event) => setRegionId(event.target.value ? Number(event.target.value) : null)}>
            <option value="">Elegí una región</option>
            {regionOptions.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
          </select>
        </div>
        {!cityMissing && (
          <div className="grid gap-1">
            <label htmlFor="cityId" className={LABEL}>Ciudad</label>
            <select key={regionId ?? "none"} id="cityId" name="cityId" defaultValue={defaults.cityId ?? ""} disabled={regionId === null} aria-invalid={invalid("cityId")} className={FIELD}>
              <option value="">Elegí una ciudad</option>
              {cityOptions.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
            </select>
          </div>
        )}
        <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="cityMissing" checked={cityMissing} onChange={(event) => setCityMissing(event.target.checked)} className="mt-1 h-5 w-5" />
          <span>Mi ciudad no está en la lista</span>
        </label>
        {cityMissing && (
          <div className="grid gap-1">
            <label htmlFor="cityName" className={LABEL}>Escribí tu ciudad</label>
            <input id="cityName" name="cityName" type="text" maxLength={80} defaultValue={missingCity?.cityName ?? ""}
              aria-describedby="cityName-help" aria-invalid={invalid("cityName")} className={FIELD} />
            <p id="cityName-help" className={HELP}>La agregamos nosotros. Tu perfil se publica cuando la ciudad esté cargada; no frena tu alta.</p>
          </div>
        )}
        <div className="grid gap-1">
          <label htmlFor="zone" className={LABEL}>Zona o barrio (opcional)</label>
          <input id="zone" name="zone" type="text" maxLength={80} defaultValue={defaults.zone} className={FIELD} />
        </div>
      </section>

      <section className="grid gap-4" aria-labelledby="sec-terapias">
        <h2 id="sec-terapias" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Tus terapias y tarifas</h2>
        <p className={HELP}>
          Elegí hasta {defaults.therapies.length} terapias. La duración y las tarifas son opcionales. Escribí solo números, por ejemplo 15000. No prometas curas.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          {([["currencyOwn", "own_country", defaults.currencyOwn], ["currencyOther", "other_countries", defaults.currencyOther]] as const).map(([name, audience, current]) => (
            <div key={name} className="grid gap-1">
              <label htmlFor={name} className={LABEL}>Moneda de la tarifa: {labelRateAudience(audience).toLowerCase()}</label>
              <select id={name} name={name} defaultValue={current ?? ""} aria-invalid={invalid(name)} className={FIELD}>
                <option value="">Sin tarifa</option>
                {catalogs.currencies.map((currency) => <option key={currency.id} value={currency.id}>{currency.code}</option>)}
              </select>
            </div>
          ))}
        </div>
        {defaults.therapies.map((slot, index) => (
          <fieldset key={index} className="grid gap-3 rounded-md border border-zinc-300 p-3 dark:border-zinc-700">
            <legend className={`${LABEL} px-1`}>Terapia {index + 1}{index === 0 ? "" : " (opcional)"}</legend>
            <div className="grid gap-1">
              <label htmlFor={`therapyId_${index}`} className={LABEL}>Terapia</label>
              <select id={`therapyId_${index}`} name={`therapyId_${index}`} defaultValue={slot.therapyId ?? ""} aria-invalid={invalid(`therapyId_${index}`)} className={FIELD}>
                <option value="">{index === 0 ? "Elegí una terapia" : "Ninguna"}</option>
                {catalogs.therapies.map((therapy) => <option key={therapy.id} value={therapy.id}>{therapy.name}</option>)}
              </select>
            </div>
            <div className="grid gap-1">
              <label htmlFor={`minutes_${index}`} className={LABEL}>Duración de la sesión, en minutos (opcional)</label>
              <input id={`minutes_${index}`} name={`minutes_${index}`} type="text" inputMode="numeric" maxLength={3} defaultValue={slot.minutes}
                aria-invalid={invalid(`minutes_${index}`)} className={FIELD} />
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="grid gap-1">
                <label htmlFor={`rateOwn_${index}`} className={LABEL}>Tarifa: {labelRateAudience("own_country").toLowerCase()} (opcional)</label>
                <input id={`rateOwn_${index}`} name={`rateOwn_${index}`} type="text" inputMode="decimal" maxLength={16} defaultValue={slot.rateOwn}
                  aria-invalid={invalid(`rateOwn_${index}`)} className={FIELD} />
              </div>
              <div className="grid gap-1">
                <label htmlFor={`rateOther_${index}`} className={LABEL}>Tarifa: {labelRateAudience("other_countries").toLowerCase()} (opcional)</label>
                <input id={`rateOther_${index}`} name={`rateOther_${index}`} type="text" inputMode="decimal" maxLength={16} defaultValue={slot.rateOther}
                  aria-invalid={invalid(`rateOther_${index}`)} className={FIELD} />
              </div>
            </div>
          </fieldset>
        ))}
      </section>

      <section className="grid gap-4" aria-labelledby="sec-atencion">
        <h2 id="sec-atencion" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Cómo atendés</h2>
        <CheckGroup legend="Modo de atención" name="serviceModes" options={catalogs.serviceModes} selected={defaults.serviceModes} label={labelServiceMode} />
        <CheckGroup legend="Formato de sesión" name="sessionFormats" options={catalogs.sessionFormats} selected={defaults.sessionFormats} label={labelSessionFormat} />
        <CheckGroup legend="Idiomas de atención" name="languages" options={catalogs.languages} selected={defaults.languages} label={labelLanguage} />
      </section>

      <section className="grid gap-4" aria-labelledby="sec-contacto">
        <h2 id="sec-contacto" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Cómo te contactan</h2>
        <p className={HELP}>Tu teléfono y tu mail solo se muestran cuando alguien aprieta &quot;Ver contacto&quot;. La web y tus redes son públicas.</p>
        <div className="grid gap-1">
          <label htmlFor="phone" className={LABEL}>Teléfono</label>
          <input id="phone" name="phone" type="tel" inputMode="tel" autoComplete="tel" required maxLength={40}
            defaultValue={defaults.phone} aria-invalid={invalid("phone")} className={FIELD} />
        </div>
        <label className="flex items-center gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="phoneWhatsapp" defaultChecked={defaults.phoneWhatsapp} className="h-5 w-5" />
          Atiendo WhatsApp en este número
        </label>
        <div className="grid gap-1">
          <label htmlFor="email" className={LABEL}>Mail de contacto (opcional)</label>
          <input id="email" name="email" type="email" inputMode="email" autoComplete="email" maxLength={254}
            defaultValue={defaults.email} aria-invalid={invalid("email")} className={FIELD} />
        </div>
        <div className="grid gap-1">
          <label htmlFor="website" className={LABEL}>Página web (opcional)</label>
          <input id="website" name="website" type="url" inputMode="url" maxLength={300}
            defaultValue={defaults.website} aria-invalid={invalid("website")} className={FIELD} />
        </div>
        <div className="grid gap-1">
          <label htmlFor="instagram" className={LABEL}>Instagram (opcional)</label>
          <input id="instagram" name="instagram" type="text" autoCapitalize="none" autoCorrect="off" spellCheck={false} maxLength={80}
            defaultValue={defaults.instagram} aria-describedby="instagram-help" aria-invalid={invalid("instagram")} className={FIELD} />
          <p id="instagram-help" className={HELP}>Solo tu usuario, por ejemplo ana.terapias. Es público: lo ve cualquiera en tu perfil.</p>
        </div>
        <div className="grid gap-1">
          <label htmlFor="facebook" className={LABEL}>Facebook (opcional)</label>
          <input id="facebook" name="facebook" type="text" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} maxLength={300}
            defaultValue={defaults.facebook} aria-describedby="facebook-help" aria-invalid={invalid("facebook")} className={FIELD} />
          <p id="facebook-help" className={HELP}>El enlace de tu página o perfil, por ejemplo facebook.com/anaterapias.</p>
        </div>
        <div className="grid gap-1">
          <label htmlFor="tiktok" className={LABEL}>TikTok (opcional)</label>
          <input id="tiktok" name="tiktok" type="text" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} maxLength={300}
            defaultValue={defaults.tiktok} aria-describedby="tiktok-help" aria-invalid={invalid("tiktok")} className={FIELD} />
          <p id="tiktok-help" className={HELP}>Tu usuario o el enlace de tu perfil, por ejemplo @ana.terapias.</p>
        </div>
        <div className="grid gap-1">
          <label htmlFor="youtube" className={LABEL}>YouTube (opcional)</label>
          <input id="youtube" name="youtube" type="text" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} maxLength={300}
            defaultValue={defaults.youtube} aria-describedby="youtube-help" aria-invalid={invalid("youtube")} className={FIELD} />
          <p id="youtube-help" className={HELP}>Tu @canal o el enlace de tu canal, por ejemplo youtube.com/@anaterapias.</p>
        </div>
      </section>

      <div className="grid gap-3 sm:grid-cols-2">
        <button type="submit" name="intent" value="save" disabled={pending}
          className="rounded-md border border-zinc-400 px-4 py-3 font-medium text-zinc-900 disabled:opacity-60 dark:text-zinc-100">
          {pending ? "Guardando…" : "Guardar borrador"}
        </button>
        <button type="submit" name="intent" value="submit" disabled={pending}
          className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900">
          {pending ? "Enviando…" : "Enviar a revisión"}
        </button>
      </div>
      <p role={state.status === "error" ? "alert" : "status"} aria-live="polite"
        className={state.status === "error" ? "text-red-700 dark:text-red-400" : "text-zinc-800 dark:text-zinc-200"}>
        {state.message}
      </p>
    </form>
  );
}
