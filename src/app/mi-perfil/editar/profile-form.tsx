"use client";

import Link from "next/link";
import { unstable_isUnrecognizedActionError } from "next/navigation";
import { useActionState, useCallback, useState, useTransition } from "react";
import { SearchableSelect } from "@/components/searchable-select";
import type { ChildOption, CatalogOption, FormCatalogs } from "@/lib/catalogs";
import { labelLanguage, labelRateAudience, labelServiceMode, labelSessionFormat } from "@/lib/labels";
import { countText, LIMITS, type FormDefaults } from "@/lib/profile-form";
import { runGuarded, STALE_MESSAGE } from "@/lib/stale-action";
import { discardDraft } from "../discard-draft-action";
import { saveProfile, type EditState } from "./actions";
import { PhotoField } from "./photo-field";

const INITIAL: EditState = { status: "idle", message: "", fields: [], flagged: [] };
// Shown when this page was opened before a deploy and the server no longer knows its action (the form stays as the person left it).
// Se muestra cuando esta página se abrió antes de un deploy y el servidor ya no conoce su acción (el formulario queda como lo dejó la persona).
const STALE: EditState = { status: "error", message: STALE_MESSAGE, fields: [], flagged: [] };
function saveGuarded(previous: EditState, data: FormData): Promise<EditState> {
  return runGuarded(() => saveProfile(previous, data), unstable_isUnrecognizedActionError, STALE);
}
const FIELD = "min-h-11 w-full rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";
const LABEL = "font-medium text-tinta";
// Chrome ignores autocomplete="off" on fields it takes for address fields; a value it does not recognize is never filled.
// Chrome ignora autocomplete="off" en campos que cree de dirección; un valor que no reconoce nunca se rellena.
const NO_AUTOFILL = "nope";
const HELP = "text-sm text-apagado";
// Looks shared by the sections and buttons of this form (same shapes as the site header and the search). / Looks compartidos por las secciones y botones de este formulario (mismas formas que el encabezado y el buscador).
const SECTION = "grid gap-4 border-t border-linea pt-6";
const SECTION_TITLE = "font-display text-xl font-semibold text-tinta";
const PRIMARY = "inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60";
const SECONDARY = "inline-flex min-h-11 items-center justify-center rounded-full border border-tinta px-5 font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60";

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
  livePhotoUrl: string | null;
  pendingPhotoUrl: string | null;
  photoLost: boolean;
  // a draft is saved in the database (so "Descartar cambios" has something to throw away besides what is on screen) / hay un borrador guardado en la base
  hasDraft: boolean;
};

// A text box with a live character counter. It NEVER cuts what the person types or pastes (no maxLength): if the text is too long
// the counter turns red and says by how much. The box grows with the text, so there is no small inner scroll area to get stuck in.
// Caja de texto con contador. NUNCA corta lo que la persona escribe o pega (sin maxLength): si el texto es largo, el contador se
// pone rojo y dice por cuánto. La caja crece con el texto, así no hay una zona de scroll chica donde trabarse.
function CountedText({ id, name, label, rows, max, multiline, defaultValue, help, invalid }: {
  id: string; name: string; label: string; rows: number; max: number; multiline: boolean; defaultValue: string; help: string; invalid: boolean;
}) {
  const [length, setLength] = useState(countText(defaultValue, multiline));
  const over = length - max;
  const fit = (element: HTMLTextAreaElement | null) => {
    if (!element) return;
    element.style.height = "auto";
    element.style.height = `${element.scrollHeight + (element.offsetHeight - element.clientHeight)}px`;
  };
  return (
    <div className="grid gap-1">
      <label htmlFor={id} className={LABEL}>{label}</label>
      <textarea id={id} name={name} rows={rows} defaultValue={defaultValue} ref={fit} aria-describedby={`${id}-help`} aria-invalid={invalid || over > 0}
        onChange={(event) => { setLength(countText(event.target.value, multiline)); fit(event.target); }} className={`${FIELD} resize-y`} />
      <p id={`${id}-help`} className={HELP}>{help} <span aria-live="off">({length}/{max})</span></p>
      {over > 0 && (
        <p role="status" className="text-sm font-medium text-peligro-texto">
          Te pasaste por {over} {over === 1 ? "carácter" : "caracteres"}. Acortá el texto para poder enviarlo: no se corta solo.
        </p>
      )}
    </div>
  );
}

function CheckGroup({ legend, name, options, selected, label }: {
  legend: string; name: string; options: { id: number; code: string }[]; selected: number[]; label: (code: string) => string;
}) {
  return (
    <fieldset className="grid gap-2">
      <legend className={LABEL}>{legend}</legend>
      {options.map((option) => (
        <label key={option.id} className="flex items-center gap-3 text-tinta">
          <input type="checkbox" name={name} value={option.id} defaultChecked={selected.includes(option.id)} className="h-5 w-5 accent-acento" />
          {label(option.code)}
        </label>
      ))}
    </fieldset>
  );
}

export function ProfileForm({ defaults, catalogs, countries, regions, cities, initialCountryId, initialRegionId, missingCity, lastRejection, livePhotoUrl, pendingPhotoUrl, photoLost, hasDraft }: Props) {
  const [state, action, pending] = useActionState(saveGuarded, INITIAL);
  const [, startTransition] = useTransition();
  const [countryId, setCountryId] = useState<number | null>(initialCountryId);
  const [regionId, setRegionId] = useState<number | null>(initialRegionId);
  // true from the first edit until the person saves or sends / true desde la primera edición hasta que guarda o envía
  const [dirty, setDirty] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  // a picture is chosen but not uploaded: saving or sending is blocked until the person uploads or cancels it / hay una imagen elegida sin subir: se bloquea guardar o enviar hasta que la suba o la cancele
  const [photoChoosing, setPhotoChoosing] = useState(false);
  const [photoWarn, setPhotoWarn] = useState(false);
  const handlePhotoChoosing = useCallback((open: boolean) => {
    setPhotoChoosing(open);
    if (!open) setPhotoWarn(false);
  }, []);
  // the "my therapy is not in the list" box starts open when a request is already written / la caja "mi terapia no está" arranca abierta si ya hay un pedido escrito
  const [suggestOpen, setSuggestOpen] = useState(defaults.suggestedTherapy !== "");
  const [discardError, setDiscardError] = useState("");
  const [cityMissing, setCityMissing] = useState<boolean>(missingCity !== null);
  const regionOptions = regions.filter((region) => region.parentId === countryId);
  const cityOptions = cities.filter((city) => city.parentId === regionId);
  // A region with no cities loaded: there is nothing to pick, so the person writes hers (no empty list, no error, no checkbox).
  // Una región sin ciudades cargadas: no hay nada para elegir, así que la persona escribe la suya (sin lista vacía, sin error, sin tilde).
  const noCities = regionId !== null && cityOptions.length === 0;
  const typedCity = cityMissing || noCities;
  const invalid = (field: string) => state.status === "error" && state.fields.includes(field);

  if (state.status === "submitted") {
    return (
      <section className="mt-6 rounded-xl border border-linea bg-superficie p-5" role="status">
        <h2 className={SECTION_TITLE}>{state.message}</h2>
        <p className="mt-1 text-apagado">Te avisamos cuando esté revisado. Mientras tanto no podés cambiarlo.</p>
        {state.flagged.length > 0 && (
          <p className="mt-2 text-apagado">
            Ojo: encontramos palabras que suelen rechazarse ({state.flagged.join(", ")}). No promete cura ni trata enfermedades: si querés, corregilas y volvé a enviar cuando te respondamos.
          </p>
        )}
        <p className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
          <Link href="/mi-perfil" className="text-acento underline underline-offset-4">Volver a mi perfil</Link>
          <Link href="/" className="text-acento underline underline-offset-4">Ir al inicio</Link>
        </p>
      </section>
    );
  }

  // "Descartar cambios": throws away the saved draft AND what is on screen, then goes back to "My profile". The published profile and
  // every photo stay as they are. It asks first, because it cannot be undone. Without a saved draft the server just sends the person back.
  // "Descartar cambios": tira el borrador guardado Y lo que hay en pantalla, y vuelve a "Mi perfil". El perfil publicado y las fotos
  // quedan como están. Pregunta antes, porque no se puede deshacer. Sin borrador guardado, el servidor solo la devuelve a "Mi perfil".
  function handleDiscard() {
    const question = hasDraft
      ? "¿Descartar los cambios guardados como borrador y lo que cambiaste en esta pantalla? No se puede deshacer. Tu perfil publicado no se modifica."
      : "¿Descartar lo que cambiaste en esta pantalla? Se pierde y no se puede deshacer. Tu perfil publicado no se modifica.";
    if (!window.confirm(question)) return;
    setDiscardError("");
    setDiscarding(true);
    setDirty(false);
    startTransition(async () => {
      const result = await runGuarded(
        () => discardDraft({ status: "idle", message: "" }),
        unstable_isUnrecognizedActionError,
        { status: "error" as const, message: "El sitio se actualizó y esta pantalla quedó vieja. Tocá «Recargar la página» y probá de nuevo." },
      );
      // on success the server redirects and this line is never reached / si salió bien el servidor redirige y esta línea no se alcanza
      setDiscarding(false);
      if (result.status === "error") setDiscardError(result.message);
    });
  }

  // React 19 empties an uncontrolled form after a form action finishes, even when the action returned an error. To keep what the
  // person typed, the submit is sent by hand: the form has no "action" prop, so it is never reset.
  // React 19 vacía un formulario no controlado cuando termina la acción, incluso si devolvió un error. Para conservar lo escrito,
  // el envío se hace a mano: el formulario no tiene prop "action", así que nunca se reinicia.
  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const submitter = (event.nativeEvent as SubmitEvent).submitter as HTMLElement | null;
    if (photoChoosing) {
      setPhotoWarn(true);
      document.getElementById("sec-foto")?.scrollIntoView({ block: "center" });
      return;
    }
    // After a rejection, sending locks the profile until it is reviewed again: ask first, so a half-corrected profile is not sent by mistake.
    // Tras un rechazo, enviar bloquea el perfil hasta que se revise de nuevo: se pregunta antes, para no enviar a medias por error.
    if (submitter?.getAttribute("value") === "submit" && lastRejection && !window.confirm("¿Ya corregiste todo lo que te pedimos? Después de enviar no podés cambiar nada hasta que lo revisemos.")) return;
    const data = new FormData(event.currentTarget, submitter);
    setDirty(false);
    startTransition(() => action(data));
  }

  return (
    <form onSubmit={handleSubmit} onChange={() => setDirty(true)} className="mt-6 grid gap-6" noValidate>
      {lastRejection && (
        <p role="note" className="rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-sm text-aviso-texto">
          Tu última revisión fue rechazada: {lastRejection}
        </p>
      )}

      <section className="grid gap-4" aria-labelledby="sec-datos">
        <h2 id="sec-datos" className={SECTION_TITLE}>Tus datos</h2>
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
        <CountedText id="about" name="about" label="Sobre mí (opcional)" rows={8} max={LIMITS.about} multiline defaultValue={defaults.about}
          invalid={invalid("about")}
          help="Contá tu formación y tu manera de trabajar, en tus palabras. Se ve solo en tu perfil completo. Sin enlaces, mails, @usuarios ni teléfonos: para eso están los campos de contacto. No prometas curas ni hables de enfermedades." />
        <div className="grid gap-1">
          <label htmlFor="practiceStartYear" className={LABEL}>Año en que empezaste a trabajar como terapeuta, en cualquier terapia (opcional)</label>
          <input id="practiceStartYear" name="practiceStartYear" type="number" inputMode="numeric" min={1900} max={2100} autoComplete={NO_AUTOFILL}
            defaultValue={defaults.practiceStartYear} aria-invalid={invalid("practiceStartYear")} className={FIELD} />
        </div>
      </section>

      <PhotoField initialNew={defaults.photoNew} initialRemove={defaults.photoRemove} initialPreviewUrl={pendingPhotoUrl} liveUrl={livePhotoUrl} lost={photoLost} onChoosing={handlePhotoChoosing} warn={photoWarn} onEdit={() => setDirty(true)} />

      <section className={SECTION} aria-labelledby="sec-lugar">
        <h2 id="sec-lugar" className={SECTION_TITLE}>Dónde atendés</h2>
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
        {!typedCity && (
          <div className="grid gap-1">
            <label htmlFor="cityId" className={LABEL}>Ciudad</label>
            <select key={regionId ?? "none"} id="cityId" name="cityId" defaultValue={defaults.cityId ?? ""} disabled={regionId === null} aria-invalid={invalid("cityId")} className={FIELD}>
              <option value="">Elegí una ciudad</option>
              {cityOptions.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
            </select>
          </div>
        )}
        {noCities ? (
          <input type="hidden" name="cityMissing" value="on" />
        ) : (
          <label className="flex items-start gap-3 text-tinta">
            <input type="checkbox" name="cityMissing" checked={cityMissing} onChange={(event) => setCityMissing(event.target.checked)} className="mt-1 h-5 w-5 accent-acento" />
            <span>Mi ciudad no está en la lista</span>
          </label>
        )}
        {typedCity && (
          <div className="grid gap-1">
            <label htmlFor="cityName" className={LABEL}>Escribí tu ciudad</label>
            <input id="cityName" name="cityName" type="text" maxLength={80} autoComplete={NO_AUTOFILL} defaultValue={missingCity?.cityName ?? ""}
              aria-describedby="cityName-help" aria-invalid={invalid("cityName")} className={FIELD} />
            <p id="cityName-help" className={HELP}>{noCities ? "Todavía no cargamos ciudades de esta región. Escribí la tuya: la agregamos nosotros. " : "La agregamos nosotros. "}Tu perfil se publica cuando la ciudad esté cargada; no frena tu alta.</p>
          </div>
        )}
        <div className="grid gap-1">
          <label htmlFor="zone" className={LABEL}>Zona o barrio (opcional)</label>
          <input id="zone" name="zone" type="text" maxLength={80} autoComplete={NO_AUTOFILL} defaultValue={defaults.zone} className={FIELD} />
        </div>
      </section>

      <section className={SECTION} aria-labelledby="sec-terapias">
        <h2 id="sec-terapias" className={SECTION_TITLE}>Tus terapias y tarifas</h2>
        <p className={HELP}>
          Elegí hasta {defaults.therapies.length} terapias. Para cada una marcá cómo la das: al menos una modalidad (presencial o a distancia) y un formato (individual o grupal). La duración y las tarifas son opcionales. Escribí solo números, por ejemplo 15000. &quot;Locales&quot; son quienes viven en el mismo país donde atendés. No prometas curas.
        </p>
        {/* Highlighted and at the TOP of the section, so it is found without scrolling through every therapy row. The checkbox has no
            name: it is not sent; only the text is (and only while the box is ticked, so unticking it clears the request).
            Resaltado y ARRIBA de la sección, para encontrarlo sin recorrer todas las filas de terapias. El tilde no tiene name: no se
            envía; solo se envía el texto (y solo mientras está tildado, así destildar borra el pedido). */}
        <div className="grid gap-3 rounded-xl border-2 border-acento bg-superficie p-4">
          <label className="flex items-start gap-3 font-medium text-tinta">
            <input type="checkbox" checked={suggestOpen} onChange={(event) => setSuggestOpen(event.target.checked)} className="mt-1 h-5 w-5 accent-acento" />
            <span>Mi terapia no está en la lista</span>
          </label>
          {suggestOpen && (
            <div className="grid gap-1">
              <label htmlFor="suggestedTherapy" className={LABEL}>Escribí el nombre de tu terapia</label>
              <input id="suggestedTherapy" name="suggestedTherapy" type="text" maxLength={LIMITS.suggestedTherapy} autoComplete={NO_AUTOFILL}
                defaultValue={defaults.suggestedTherapy} aria-describedby="suggestedTherapy-help" aria-invalid={invalid("suggestedTherapy")} className={FIELD} />
              <p id="suggestedTherapy-help" className={HELP}>
                Escribí solo el nombre (hasta 3, separadas por coma). Lo evaluamos y, si la agregamos, te avisamos para que la elijas. No se publica en tu perfil.
              </p>
            </div>
          )}
        </div>
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
          <fieldset key={index} className="grid gap-3 rounded-xl border border-linea bg-superficie p-4">
            <legend className={`${LABEL} px-2`}>Terapia {index + 1}{index === 0 ? "" : " (opcional)"}</legend>
            <div className="grid gap-1">
              <label htmlFor={`therapyId_${index}`} className={LABEL}>Terapia</label>
              <SearchableSelect id={`therapyId_${index}`} name={`therapyId_${index}`} options={catalogs.therapies}
                emptyLabel={index === 0 ? "Elegí una terapia" : "Ninguna"} listLabel="Terapias" defaultValue={String(slot.therapyId ?? "")}
                variant="plain" invalid={invalid(`therapyId_${index}`)} onSelect={() => setDirty(true)} />
            </div>
            <CountedText id={`description_${index}`} name={`description_${index}`} label="Descripción breve de esta terapia (opcional)" rows={3} max={LIMITS.therapyDescription} multiline={false}
              defaultValue={slot.description} invalid={invalid(`description_${index}`)}
              help="Qué técnicas usás o cómo es tu sesión. Se ve en tu perfil completo. Sin enlaces ni teléfonos." />
            <CheckGroup legend="Modo de atención de esta terapia" name={`serviceModes_${index}`} options={catalogs.serviceModes} selected={slot.serviceModes} label={labelServiceMode} />
            <CheckGroup legend="Formato de sesión de esta terapia" name={`sessionFormats_${index}`} options={catalogs.sessionFormats} selected={slot.sessionFormats} label={labelSessionFormat} />
            <div className="grid gap-1">
              <label htmlFor={`minutes_${index}`} className={LABEL}>Duración de la sesión, en minutos (opcional)</label>
              <input id={`minutes_${index}`} name={`minutes_${index}`} type="text" inputMode="numeric" maxLength={3} autoComplete={NO_AUTOFILL} defaultValue={slot.minutes}
                aria-invalid={invalid(`minutes_${index}`)} className={FIELD} />
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="grid gap-1">
                <label htmlFor={`rateOwn_${index}`} className={LABEL}>Tarifa para pacientes locales (opcional)</label>
                <input id={`rateOwn_${index}`} name={`rateOwn_${index}`} type="text" inputMode="decimal" maxLength={16} autoComplete={NO_AUTOFILL} defaultValue={slot.rateOwn}
                  aria-invalid={invalid(`rateOwn_${index}`)} className={FIELD} />
              </div>
              <div className="grid gap-1">
                <label htmlFor={`rateOther_${index}`} className={LABEL}>Tarifa para pacientes del exterior (opcional)</label>
                <input id={`rateOther_${index}`} name={`rateOther_${index}`} type="text" inputMode="decimal" maxLength={16} autoComplete={NO_AUTOFILL} defaultValue={slot.rateOther}
                  aria-invalid={invalid(`rateOther_${index}`)} className={FIELD} />
              </div>
            </div>
          </fieldset>
        ))}
      </section>

      <section className={SECTION} aria-labelledby="sec-atencion">
        <h2 id="sec-atencion" className={SECTION_TITLE}>Idiomas</h2>
        <CheckGroup legend="Idiomas de atención" name="languages" options={catalogs.languages} selected={defaults.languages} label={labelLanguage} />
      </section>

      <section className={SECTION} aria-labelledby="sec-contacto">
        <h2 id="sec-contacto" className={SECTION_TITLE}>Cómo te contactan</h2>
        <p className={HELP}>Tu teléfono y tu mail solo se muestran cuando alguien aprieta &quot;Ver contacto&quot;. La web y tus redes son públicas.</p>
        <div className="grid gap-1">
          <label htmlFor="phone" className={LABEL}>Teléfono</label>
          <input id="phone" name="phone" type="tel" inputMode="tel" autoComplete="tel" required maxLength={40}
            defaultValue={defaults.phone} aria-invalid={invalid("phone")} className={FIELD} />
        </div>
        <label className="flex items-center gap-3 text-tinta">
          <input type="checkbox" name="phoneWhatsapp" defaultChecked={defaults.phoneWhatsapp} className="h-5 w-5 accent-acento" />
          Atiendo WhatsApp en este número
        </label>
        <p className={HELP}>Para que aparezca el botón de WhatsApp, escribí el número con + y el código de país, por ejemplo +54 9 298 4000000.</p>
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

      {/* always reachable: the buttons stay at the bottom of the screen while there is something unsent / siempre a mano: los botones quedan al pie mientras haya algo sin enviar */}
      <div className="sticky bottom-0 -mx-2 grid gap-2 border-t border-linea bg-fondo px-2 py-3">
        {(dirty || state.status === "error") && (
          <p role="status" className="rounded-lg border border-aviso-borde bg-aviso-fondo p-2 text-sm text-aviso-texto">
            Tenés cambios sin enviar. Seguí corrigiendo todo lo que quieras y, cuando termines, apretá «Enviar a revisión». Si salís de esta pantalla antes, se pierden.
          </p>
        )}
        <div className="grid grid-cols-2 gap-3">
          <button type="submit" name="intent" value="save" disabled={pending}
            className={SECONDARY}>
            {pending ? "Guardando…" : "Guardar y seguir"}
          </button>
          <button type="submit" name="intent" value="exit" disabled={pending}
            className={SECONDARY}>
            {pending ? "Guardando…" : "Guardar y volver"}
          </button>
          <button type="submit" name="intent" value="submit" disabled={pending}
            className={`col-span-2 ${PRIMARY}`}>
            {pending ? "Enviando…" : "Enviar a revisión"}
          </button>
          {/* the preview shows what is SAVED: it is off while there is something unsaved or a picture waiting to be uploaded / la vista previa muestra lo GUARDADO: está apagada mientras haya algo sin guardar o una imagen sin subir */}
          {dirty || state.status === "error" || photoChoosing || pending ? (
            <button type="button" disabled className={`col-span-2 ${SECONDARY}`}>
              Ver vista previa (guardá primero)
            </button>
          ) : (
            <Link href="/mi-perfil/vista-previa" target="_blank" rel="noopener noreferrer" className={`col-span-2 ${SECONDARY}`}>
              Ver vista previa<span className="sr-only"> (se abre en otra pestaña)</span>
            </Link>
          )}
          {(hasDraft || dirty) && (
            <button type="button" onClick={handleDiscard} disabled={pending || discarding}
              className={`col-span-2 ${SECONDARY}`}>
              {discarding ? "Descartando…" : "Descartar cambios"}
            </button>
          )}
        </div>
        {discardError && <p role="alert" className="text-peligro-texto">{discardError}</p>}
        <p role={state.status === "error" ? "alert" : "status"} aria-live="polite"
          className={state.status === "error" ? "text-peligro-texto" : "text-tinta"}>
          {state.message}
        </p>
        {state.message === STALE_MESSAGE && (
          <button type="button" onClick={() => window.location.reload()}
            className={SECONDARY}>
            Recargar la página
          </button>
        )}
      </div>
    </form>
  );
}
