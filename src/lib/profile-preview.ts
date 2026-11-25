// Preview of the therapist's OWN profile: turns what is saved (the form values) into the same data the public pages use, so the
// preview is drawn by the same code as the real profile and the real search card. PURE code: no database, nothing is written.
// SECURITY: the text of a draft is written by the therapist, so it is shown only as text, and links go through the same strict
// checks as the public profile (toProfileDetail / buildLinks). The phone and the mail are NOT part of the result.
// Vista previa del PROPIO perfil del terapeuta: convierte lo guardado (los valores del formulario) en los mismos datos que usan las
// páginas públicas, así la vista previa la dibuja el mismo código que el perfil real y la tarjeta real de la búsqueda. Código PURO:
// sin base, no se escribe nada. SEGURIDAD: el texto de un borrador lo escribe el terapeuta, así que se muestra solo como texto, y los
// enlaces pasan por las mismas revisiones estrictas del perfil público. El teléfono y el mail NO forman parte del resultado.

import type { FormCatalogs, LocationTree } from "@/lib/catalogs";
import { toProfileDetail, type DetailRow, type ProfileDetail } from "@/lib/profile-detail";
import { AUDIENCE_CODES, parseAmount, type FormDefaults, type TherapyDefaults } from "@/lib/profile-form";
import { toCard, type SearchCard, type SearchRow } from "@/lib/search";

// Where the preview comes from, so the page can say it in words. / De dónde sale la vista previa, para que la página lo diga con palabras.
export type PreviewSource = "draft" | "in_review" | "rejected" | "live";

// Which photo the preview shows: a pending one (private bucket, shown with a short-lived address), the live one, or none.
// Qué foto muestra la vista previa: una pendiente (bucket privado, con dirección de corta vida), la vigente o ninguna.
export type PreviewPhoto = { kind: "pending"; path: string } | { kind: "live"; path: string } | { kind: "none" };

export type PreviewInput = {
  profileId: string;
  defaults: FormDefaults;
  catalogs: FormCatalogs;
  tree: LocationTree;
  // ISO code of the country of the chosen city (the flag), or null / código ISO del país de la ciudad elegida (la bandera), o null
  countryIso: string | null;
  isPinned: boolean;
  // therapy id -> short name for the card; a therapy without one uses its full name / id de terapia -> nombre corto para la tarjeta
  shortNames: ReadonlyMap<number, string>;
  // path of the photo that is live today in the public bucket, or null / ruta de la foto que hoy está vigente en el bucket público, o null
  livePhotoPath: string | null;
};

export type Preview = { card: SearchCard; detail: ProfileDetail; photo: PreviewPhoto };

type Coded = { id: number; code: string };
type FilledSlot = TherapyDefaults & { therapyId: number };

const codesOf = (list: readonly Coded[], ids: readonly number[]): string[] => list.filter((item) => ids.includes(item.id)).map((item) => item.code);
const orNull = (value: string): string | null => (value.trim() === "" ? null : value.trim());

// A rate counts only with a valid positive amount AND a currency; otherwise it is left out (the profile then says "consultar").
// Una tarifa cuenta solo con un monto válido y positivo Y una moneda; si no, se omite (el perfil dice "consultar").
function rateOf(audience: string, raw: string, currencyId: number | null, currencies: FormCatalogs["currencies"]): { audience: string; amount: number; currency: string }[] {
  const amount = parseAmount(raw);
  const currency = currencies.find((item) => item.id === currencyId)?.code;
  return amount !== null && Number.isFinite(amount) && amount > 0 && currency ? [{ audience, amount, currency }] : [];
}

// null when there is not even a public name: there is nothing to draw yet. / null si ni siquiera hay nombre público: todavía no hay nada para dibujar.
export function buildPreview(input: PreviewInput): Preview | null {
  const { defaults, catalogs, tree } = input;
  const displayName = defaults.displayName.trim();
  if (displayName === "") return null;

  const city = tree.cities.find((option) => option.id === defaults.cityId);
  const region = tree.regions.find((option) => option.id === city?.parentId);
  const country = tree.countries.find((option) => option.id === region?.parentId);

  const slots = defaults.therapies.filter((slot): slot is FilledSlot => slot.therapyId !== null);
  const therapies = slots.flatMap((slot) => {
    const name = catalogs.therapies.find((option) => option.id === slot.therapyId)?.name;
    // a therapy that is not in the active catalog cannot be shown (the public pages hide it too) / una terapia fuera del catálogo activo no se puede mostrar (las páginas públicas también la ocultan)
    if (!name) return [];
    const minutes = /^\d{1,3}$/.test(slot.minutes.trim()) ? Number(slot.minutes.trim()) : null;
    return [{
      therapy_id: slot.therapyId,
      name,
      description: orNull(slot.description),
      session_minutes: minutes,
      service_modes: codesOf(catalogs.serviceModes, slot.serviceModes),
      session_formats: codesOf(catalogs.sessionFormats, slot.sessionFormats),
      rates: [
        ...rateOf(AUDIENCE_CODES.own, slot.rateOwn, defaults.currencyOwn, catalogs.currencies),
        ...rateOf(AUDIENCE_CODES.other, slot.rateOther, defaults.currencyOther, catalogs.currencies),
      ],
    }];
  });
  const byId = [...therapies].sort((a, b) => a.therapy_id - b.therapy_id);
  const union = (pick: (item: (typeof therapies)[number]) => string[], order: readonly Coded[]): string[] =>
    order.map((item) => item.code).filter((code) => therapies.some((item) => pick(item).includes(code)));

  const photo: PreviewPhoto = defaults.photoRemove
    ? { kind: "none" }
    : defaults.photoNew
      ? { kind: "pending", path: defaults.photoNew }
      : input.livePhotoPath
        ? { kind: "live", path: input.livePhotoPath }
        : { kind: "none" };
  const photoPath = photo.kind === "live" ? photo.path : null;

  const common = {
    profile_id: input.profileId,
    display_name: displayName,
    photo_path: photoPath,
    headline: orNull(defaults.headline),
    city_name: city?.name ?? null,
    region_name: region?.name ?? null,
    country_name: country?.name ?? null,
    country_iso: input.countryIso,
    languages: codesOf(catalogs.languages, defaults.languages),
    is_pinned: input.isPinned,
  };

  const cardRow: SearchRow = {
    ...common,
    therapy_ids: byId.map((item) => item.therapy_id),
    therapy_names: byId.map((item) => item.name),
    therapy_short_names: byId.map((item) => input.shortNames.get(item.therapy_id)?.trim() || item.name),
    service_modes: union((item) => item.service_modes, catalogs.serviceModes),
    session_formats: union((item) => item.session_formats, catalogs.sessionFormats),
  };
  const detailRow: DetailRow = {
    ...common,
    about: orNull(defaults.about),
    practice_start_year: /^\d{4}$/.test(defaults.practiceStartYear.trim()) ? Number(defaults.practiceStartYear.trim()) : null,
    // a draft has no confirmation date for the prices: the preview does not show that line / un borrador no tiene fecha de confirmación de precios: la vista previa no muestra esa línea
    rates_confirmed_at: null,
    rates_current: false,
    website: orNull(defaults.website),
    instagram: orNull(defaults.instagram),
    facebook: orNull(defaults.facebook),
    tiktok: orNull(defaults.tiktok),
    youtube: orNull(defaults.youtube),
    therapies_detail: therapies,
  };

  const card = toCard(cardRow);
  const detail = toProfileDetail(detailRow);
  return card && detail ? { card, detail, photo } : null;
}
