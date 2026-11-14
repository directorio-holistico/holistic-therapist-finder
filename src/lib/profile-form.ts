// Rules of the therapist profile form (part A: basic data, location, languages, modes, formats, contacts).
// Pure code shared by the server action, the page and the tests. The database repeats these rules when a revision is
// approved (apply_revision_payload and the table triggers); here they only give clear messages early.
// Reglas del formulario de perfil del terapeuta (parte A: datos básicos, ubicación, idiomas, modos, formatos, contactos).
// Código puro compartido por la acción del servidor, la página y las pruebas. La base repite estas reglas al aprobar una
// revisión (apply_revision_payload y los triggers de las tablas); acá solo dan mensajes claros y temprano.

import { z } from "zod";

export const LIMITS = {
  displayName: 80,
  headline: 280,
  zone: 80,
  cityName: 80,
  contactValue: 300,
  earliestYear: 1900,
  minMinutes: 5,
  maxMinutes: 480,
  maxAmount: 100_000_000,
} as const;

// How many therapies the form offers. The database enforces the real limit (setting max_therapies_per_profile, 4 at launch).
// Cuántas terapias ofrece el formulario. La base impone el límite real (ajuste max_therapies_per_profile, 4 al lanzar).
export const MAX_THERAPIES = 4;

// Rates are for two audiences (codes of the rate_audiences catalog). / Las tarifas son para dos audiencias (códigos del catálogo).
export const AUDIENCE_CODES = { own: "own_country", other: "other_countries" } as const;
export type AudienceIds = { own: number; other: number };

// "15000", "15.000", "15.000,50", "15000,5" or "15.5" -> number. Empty -> null. Anything else -> NaN.
// A dot followed by exactly three digits is a thousands separator (Argentine style).
// "15000", "15.000", "15.000,50", "15000,5" o "15.5" -> número. Vacío -> null. Cualquier otra cosa -> NaN.
// Un punto seguido de exactamente tres dígitos es separador de miles (estilo argentino).
export function parseAmount(raw: string): number | null {
  const value = raw.replace(/\s+/g, "");
  if (value === "") return null;
  if (/^\d{1,3}(\.\d{3})+(,\d{1,2})?$/.test(value)) return Number(value.replace(/\./g, "").replace(",", "."));
  if (/^\d+([.,]\d{1,2})?$/.test(value)) return Number(value.replace(",", "."));
  return Number.NaN;
}

// Each row carries its OWN service modes and session formats (a therapist may give one therapy in person and another remote).
// Cada fila lleva SUS PROPIAS modalidades y formatos de sesión (un terapeuta puede dar una terapia presencial y otra a distancia).
export type TherapySlotInput = { therapyId: number | null; minutes: string; rateOwn: string; rateOther: string; serviceModes: number[]; sessionFormats: number[] };
export type TherapySlot = { therapyId: number; minutes: number | null; rateOwn: number | null; rateOther: number | null; serviceModes: number[]; sessionFormats: number[] };
type SlotResult = { skip: true } | { skip: false; value: TherapySlot } | { skip: false; error: { message: string; field: string } };

// One row of the therapies block: empty rows are skipped; a half filled row is an error. / Una fila del bloque de terapias.
export function readTherapySlot(slot: TherapySlotInput, index: number): SlotResult {
  const minutesText = slot.minutes.trim();
  const own = parseAmount(slot.rateOwn);
  const other = parseAmount(slot.rateOther);
  if (slot.therapyId === null) {
    if (minutesText === "" && own === null && other === null && slot.serviceModes.length === 0 && slot.sessionFormats.length === 0) return { skip: true };
    return { skip: false, error: { message: `Terapia ${index + 1}: elegí la terapia o vaciá toda la fila (duración, tarifas, modalidad y formato).`, field: `therapyId_${index}` } };
  }
  let minutes: number | null = null;
  if (minutesText !== "") {
    minutes = /^\d{1,3}$/.test(minutesText) ? Number(minutesText) : Number.NaN;
    if (!(minutes >= LIMITS.minMinutes && minutes <= LIMITS.maxMinutes)) {
      return { skip: false, error: { message: `Duración: entre ${LIMITS.minMinutes} y ${LIMITS.maxMinutes} minutos.`, field: `minutes_${index}` } };
    }
  }
  if (slot.serviceModes.length === 0) {
    return { skip: false, error: { message: `Terapia ${index + 1}: elegí al menos una modalidad de atención (presencial o a distancia).`, field: `serviceModes_${index}` } };
  }
  if (slot.sessionFormats.length === 0) {
    return { skip: false, error: { message: `Terapia ${index + 1}: elegí al menos un formato de sesión (individual o grupal).`, field: `sessionFormats_${index}` } };
  }
  const rates: [string, number | null][] = [[`rateOwn_${index}`, own], [`rateOther_${index}`, other]];
  for (const [field, amount] of rates) {
    if (amount === null) continue;
    if (Number.isNaN(amount)) return { skip: false, error: { message: "Tarifa inválida: usá solo números (por ejemplo 15000 o 15000,50).", field } };
    if (amount <= 0) return { skip: false, error: { message: "La tarifa debe ser mayor que cero. Si no querés mostrarla, dejala vacía.", field } };
    if (amount > LIMITS.maxAmount) return { skip: false, error: { message: "La tarifa es demasiado alta.", field } };
  }
  return { skip: false, value: { therapyId: slot.therapyId, minutes, rateOwn: own, rateOther: other, serviceModes: slot.serviceModes, sessionFormats: slot.sessionFormats } };
}

const hasDecimals = (amount: number, minorUnits: number) => {
  const scaled = amount * 10 ** minorUnits;
  return Math.abs(scaled - Math.round(scaled)) > 1e-6;
};

// Contact type codes used by the form (the ids come from the catalog). / Códigos de tipo de contacto del formulario.
export const CONTACT_CODES = {
  phone: "phone", email: "email", website: "website", instagram: "instagram", facebook: "facebook", tiktok: "tiktok", youtube: "youtube",
} as const;

const oneLine = (value: string) => value.replace(/\s+/g, " ").trim();
const emptyToNull = (value: string) => (value === "" ? null : value);

const optionalText = (max: number, label: string) =>
  z
    .string()
    .transform(oneLine)
    .pipe(z.string().max(max, `${label}: máximo ${max} caracteres.`))
    .transform(emptyToNull);

const idList = (message: string) =>
  z.array(z.number().int().positive()).min(1, message).max(20, "Elegiste demasiadas opciones.");

export function phoneIsValid(value: string): boolean {
  return /^\+?[0-9 ()-]+$/.test(value) && value.replace(/[^0-9]/g, "").length >= 6 && value.replace(/[^0-9]/g, "").length <= 15;
}

// Instagram: the user name only. Accepts "@user", "user" or a profile link and keeps "user" in lower case (the database stores
// exactly that format). / Instagram: solo el usuario. Acepta "@usuario", "usuario" o un enlace y deja "usuario" en minúsculas.
export function normalizeInstagram(raw: string): string {
  const withoutLink = raw
    .trim()
    .replace(/^(?:https?:\/\/)?(?:www\.)?instagram\.com\//i, "")
    .replace(/^@+/, "");
  return (withoutLink.split(/[?#/]/)[0] ?? "").toLowerCase();
}
export const instagramIsValid = (value: string) => /^[a-z0-9._]{1,30}$/.test(value);

// Facebook, TikTok and YouTube: stored as the profile LINK (https only, only these sites, profile pages only). The form accepts a
// pasted link, a link without "https://" or just the user name, and rebuilds the clean link; the database checks the same shape.
// Facebook, TikTok y YouTube: se guarda el ENLACE del perfil (solo https, solo esos sitios, solo páginas de perfil). El formulario
// acepta un enlace pegado, un enlace sin "https://" o solo el usuario, y rearma el enlace limpio; la base verifica la misma forma.
export type SocialKind = "facebook" | "tiktok" | "youtube";

const SOCIAL_VALID: Record<SocialKind, RegExp> = {
  facebook: /^https:\/\/(www\.|m\.)?(facebook\.com|fb\.com)\/[^ ]+$/,
  tiktok: /^https:\/\/(www\.)?tiktok\.com\/@[A-Za-z0-9._]{2,24}\/?$/,
  youtube: /^https:\/\/(www\.|m\.)?youtube\.com\/(@[A-Za-z0-9._-]{3,30}|channel\/UC[A-Za-z0-9_-]{22}|c\/[A-Za-z0-9._-]+|user\/[A-Za-z0-9._-]+)\/?$/,
};
const SOCIAL_FROM_HANDLE: Record<SocialKind, (handle: string) => string> = {
  facebook: (handle) => `https://www.facebook.com/${handle}`,
  tiktok: (handle) => `https://www.tiktok.com/@${handle}`,
  youtube: (handle) => `https://www.youtube.com/@${handle}`,
};
const SOCIAL_HOST = /^(?:https?:\/\/)?(?:[a-z0-9-]+\.)?(?:facebook\.com|fb\.com|tiktok\.com|youtube\.com)(?:[/?#]|$)/i;

export function normalizeSocialLink(kind: SocialKind, raw: string): string {
  const input = raw.trim();
  if (input === "" || /\s/.test(input)) return input;
  const hasScheme = /^https?:\/\//i.test(input);
  const candidate = hasScheme ? input : SOCIAL_HOST.test(input) ? `https://${input}` : SOCIAL_FROM_HANDLE[kind](input.replace(/^@+/, ""));
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return input;
  }
  // tracking parameters and fragments are dropped; Facebook's profile.php needs its id / se quitan parámetros de seguimiento
  const keepSearch = kind === "facebook" && url.pathname.toLowerCase() === "/profile.php" ? url.search : "";
  return `https://${url.hostname.toLowerCase()}${url.pathname}${keepSearch}`;
}
export const socialLinkIsValid = (kind: SocialKind, value: string) => SOCIAL_VALID[kind].test(value);

const SOCIAL_MESSAGES: Record<SocialKind, string> = {
  facebook: "Facebook inválido: pegá el enlace de tu página o perfil (facebook.com/…).",
  tiktok: "TikTok inválido: pegá el enlace de tu perfil (tiktok.com/@usuario) o solo tu usuario.",
  youtube: "YouTube inválido: pegá el enlace de tu canal (youtube.com/@canal) o solo tu @canal.",
};
const socialField = (kind: SocialKind) =>
  z
    .string()
    .transform((value) => normalizeSocialLink(kind, value))
    .pipe(z.string().max(LIMITS.contactValue, "El enlace es demasiado largo."))
    .transform(emptyToNull)
    .refine((value) => value === null || socialLinkIsValid(kind, value), SOCIAL_MESSAGES[kind]);

export function buildProfileFormSchema(maxYear: number, currencyMinorUnits: ReadonlyMap<number, number> = new Map()) {
  return z
    .object({
      displayName: z
        .string()
        .transform(oneLine)
        .pipe(z.string().min(2, "Escribí el nombre que se va a mostrar.").max(LIMITS.displayName, `Nombre: máximo ${LIMITS.displayName} caracteres.`)),
      headline: optionalText(LIMITS.headline, "Frase de presentación"),
      zone: optionalText(LIMITS.zone, "Zona o barrio"),
      practiceStartYear: z
        .number()
        .int()
        .min(LIMITS.earliestYear, `El año de inicio debe ser ${LIMITS.earliestYear} o posterior.`)
        .max(maxYear, "El año de inicio no puede ser futuro.")
        .nullable(),
      cityMissing: z.boolean(),
      cityId: z.number().int().positive().nullable(),
      regionId: z.number().int().positive().nullable(),
      cityName: optionalText(LIMITS.cityName, "Ciudad"),
      languages: idList("Elegí al menos un idioma de atención."),
      phone: z
        .string()
        .transform(oneLine)
        .pipe(z.string().min(1, "El teléfono es obligatorio."))
        .refine(phoneIsValid, "Teléfono inválido: usá solo números, espacios, paréntesis, guiones y un + al inicio (6 a 15 dígitos)."),
      phoneWhatsapp: z.boolean(),
      email: z
        .string()
        .transform((value) => value.trim().toLowerCase())
        .pipe(z.string().max(LIMITS.contactValue))
        .transform(emptyToNull)
        .refine((value) => value === null || /^[^@ ]+@[^@ ]+\.[^@ ]+$/.test(value), "Mail inválido: nombre@dominio.com."),
      website: z
        .string()
        .transform((value) => value.trim())
        .pipe(z.string().max(LIMITS.contactValue))
        .transform(emptyToNull)
        .transform((value) => (value !== null && !/^https?:\/\//i.test(value) ? `https://${value}` : value))
        .refine((value) => value === null || /^https?:\/\/[^ ]+$/.test(value), "Web inválida: debe empezar con http:// o https://."),
      instagram: z
        .string()
        .transform(normalizeInstagram)
        .transform(emptyToNull)
        .refine((value) => value === null || instagramIsValid(value), "Instagram inválido: solo tu usuario (letras, números, punto y guion bajo, hasta 30)."),
      facebook: socialField("facebook"),
      tiktok: socialField("tiktok"),
      youtube: socialField("youtube"),
      therapies: z
        .array(z.object({
          therapyId: z.number().int().positive().nullable(),
          minutes: z.string(),
          rateOwn: z.string(),
          rateOther: z.string(),
          serviceModes: z.array(z.number().int().positive()).max(20, "Elegiste demasiadas opciones."),
          sessionFormats: z.array(z.number().int().positive()).max(20, "Elegiste demasiadas opciones."),
        }))
        .max(MAX_THERAPIES),
      currencyOwn: z.number().int().positive().nullable(),
      currencyOther: z.number().int().positive().nullable(),
    })
    .superRefine((value, ctx) => {
      // therapies and rates / terapias y tarifas
      const slots = value.therapies.map((slot, index) => readTherapySlot(slot, index));
      const seen = new Set<number>();
      let ownAmounts = false;
      let otherAmounts = false;
      slots.forEach((slot, index) => {
        if (slot.skip) return;
        if ("error" in slot) {
          ctx.addIssue({ code: "custom", message: slot.error.message, path: [slot.error.field] });
          return;
        }
        if (seen.has(slot.value.therapyId)) ctx.addIssue({ code: "custom", message: "Repetiste una terapia: cada una va una sola vez.", path: [`therapyId_${index}`] });
        seen.add(slot.value.therapyId);
        ownAmounts ||= slot.value.rateOwn !== null;
        otherAmounts ||= slot.value.rateOther !== null;
      });
      if (slots.every((slot) => slot.skip)) {
        ctx.addIssue({ code: "custom", message: "Elegí al menos una terapia.", path: ["therapyId_0"] });
      }
      const checkCurrency = (used: boolean, currencyId: number | null, field: string, audience: string, pick: (slot: TherapySlot) => number | null) => {
        if (!used) return;
        const minor = currencyId === null ? undefined : currencyMinorUnits.get(currencyId);
        if (minor === undefined) {
          ctx.addIssue({ code: "custom", message: `Elegí la moneda de la tarifa para ${audience}.`, path: [field] });
          return;
        }
        for (const slot of slots) {
          if (slot.skip || "error" in slot) continue;
          const amount = pick(slot.value);
          if (amount !== null && hasDecimals(amount, minor)) {
            ctx.addIssue({ code: "custom", message: "Esa moneda no admite tantos decimales.", path: [field] });
            return;
          }
        }
      };
      checkCurrency(ownAmounts, value.currencyOwn, "currencyOwn", "residentes en tu país", (slot) => slot.rateOwn);
      checkCurrency(otherAmounts, value.currencyOther, "currencyOther", "personas de otros países", (slot) => slot.rateOther);

      if (value.cityMissing) {
        if (value.regionId === null) ctx.addIssue({ code: "custom", message: "Elegí la región de tu ciudad.", path: ["regionId"] });
        if (value.cityName === null || value.cityName.length < 2) {
          ctx.addIssue({ code: "custom", message: "Escribí el nombre de tu ciudad (mínimo 2 letras).", path: ["cityName"] });
        }
      } else if (value.cityId === null) {
        ctx.addIssue({ code: "custom", message: "Elegí tu ciudad, o marcá que no está en la lista.", path: ["cityId"] });
      }
    })
    // after validation: the rows become clean values (empty rows dropped; a currency without amounts is ignored)
    // después de validar: las filas pasan a valores limpios (se descartan las vacías; una moneda sin montos se ignora)
    .transform((value) => {
      const therapies = value.therapies.flatMap((slot, index) => {
        const read = readTherapySlot(slot, index);
        return !read.skip && "value" in read ? [read.value] : [];
      });
      return {
        ...value,
        therapies,
        currencyOwn: therapies.some((slot) => slot.rateOwn !== null) ? value.currencyOwn : null,
        currencyOther: therapies.some((slot) => slot.rateOther !== null) ? value.currencyOther : null,
      };
    });
}

export type ProfileFormValues = z.infer<ReturnType<typeof buildProfileFormSchema>>;

// HTML forms send text. Numbers and lists are converted here, anything unreadable becomes null / an empty list.
// Los formularios HTML mandan texto. Los números y listas se convierten acá; lo ilegible queda en null / lista vacía.
function toInt(value: FormDataEntryValue | null): number | null {
  if (typeof value !== "string" || !/^[0-9]{1,9}$/.test(value.trim())) return null;
  return Number(value.trim());
}
function toIntList(values: FormDataEntryValue[]): number[] {
  return values.map(toInt).filter((value): value is number => value !== null);
}
const text = (value: FormDataEntryValue | null) => (typeof value === "string" ? value : "");

export function readProfileForm(formData: FormData, maxYear: number, currencyMinorUnits: ReadonlyMap<number, number> = new Map()) {
  const therapies = Array.from({ length: MAX_THERAPIES }, (_, index) => ({
    therapyId: toInt(formData.get(`therapyId_${index}`)),
    minutes: text(formData.get(`minutes_${index}`)),
    rateOwn: text(formData.get(`rateOwn_${index}`)),
    rateOther: text(formData.get(`rateOther_${index}`)),
    serviceModes: toIntList(formData.getAll(`serviceModes_${index}`)),
    sessionFormats: toIntList(formData.getAll(`sessionFormats_${index}`)),
  }));
  return buildProfileFormSchema(maxYear, currencyMinorUnits).safeParse({
    displayName: text(formData.get("displayName")),
    headline: text(formData.get("headline")),
    zone: text(formData.get("zone")),
    practiceStartYear: toInt(formData.get("practiceStartYear")),
    cityMissing: formData.get("cityMissing") === "on",
    cityId: toInt(formData.get("cityId")),
    regionId: toInt(formData.get("regionId")),
    cityName: text(formData.get("cityName")),
    languages: toIntList(formData.getAll("languages")),
    phone: text(formData.get("phone")),
    phoneWhatsapp: formData.get("phoneWhatsapp") === "on",
    email: text(formData.get("email")),
    website: text(formData.get("website")),
    instagram: text(formData.get("instagram")),
    facebook: text(formData.get("facebook")),
    tiktok: text(formData.get("tiktok")),
    youtube: text(formData.get("youtube")),
    therapies,
    currencyOwn: toInt(formData.get("currencyOwn")),
    currencyOther: toInt(formData.get("currencyOther")),
  });
}

export type ContactTypeIds = { phone: number; email: number; website: number; instagram: number; facebook: number; tiktok: number; youtube: number };

export type ProfilePayload = {
  display_name: string;
  headline: string | null;
  zone: string | null;
  practice_start_year: number | null;
  location_id: number | null;
  languages: number[];
  contacts: { contact_type_id: number; value: string; accepts_whatsapp: boolean }[];
  therapies: {
    therapy_id: number;
    session_minutes: number | null;
    service_modes: number[];
    session_formats: number[];
    rates: { rate_audience_id: number; amount: number; currency_id: number }[];
  }[];
};

const unique = (ids: number[]) => [...new Set(ids)].sort((a, b) => a - b);

// The revision payload (keys known by submit_revision / apply_revision_payload). When the city is not listed, location_id is
// null and the city travels in location_requests (the administrator adds it before approving).
// El payload de la revisión (claves que conocen submit_revision / apply_revision_payload). Si la ciudad no está en la lista,
// location_id va en null y la ciudad viaja en location_requests (el administrador la carga antes de aprobar).
export function buildPayload(values: ProfileFormValues, contactTypes: ContactTypeIds, audiences: AudienceIds): ProfilePayload {
  const contacts: ProfilePayload["contacts"] = [
    { contact_type_id: contactTypes.phone, value: values.phone, accepts_whatsapp: values.phoneWhatsapp },
  ];
  if (values.email !== null) contacts.push({ contact_type_id: contactTypes.email, value: values.email, accepts_whatsapp: false });
  if (values.website !== null) contacts.push({ contact_type_id: contactTypes.website, value: values.website, accepts_whatsapp: false });
  if (values.instagram !== null) contacts.push({ contact_type_id: contactTypes.instagram, value: values.instagram, accepts_whatsapp: false });
  if (values.facebook !== null) contacts.push({ contact_type_id: contactTypes.facebook, value: values.facebook, accepts_whatsapp: false });
  if (values.tiktok !== null) contacts.push({ contact_type_id: contactTypes.tiktok, value: values.tiktok, accepts_whatsapp: false });
  if (values.youtube !== null) contacts.push({ contact_type_id: contactTypes.youtube, value: values.youtube, accepts_whatsapp: false });
  return {
    display_name: values.displayName,
    headline: values.headline,
    zone: values.zone,
    practice_start_year: values.practiceStartYear,
    location_id: values.cityMissing ? null : values.cityId,
    languages: unique(values.languages),
    contacts,
    therapies: values.therapies.map((slot) => {
      const rates: ProfilePayload["therapies"][number]["rates"] = [];
      if (slot.rateOwn !== null && values.currencyOwn !== null) rates.push({ rate_audience_id: audiences.own, amount: slot.rateOwn, currency_id: values.currencyOwn });
      if (slot.rateOther !== null && values.currencyOther !== null) rates.push({ rate_audience_id: audiences.other, amount: slot.rateOther, currency_id: values.currencyOther });
      return {
        therapy_id: slot.therapyId,
        session_minutes: slot.minutes,
        service_modes: unique(slot.serviceModes),
        session_formats: unique(slot.sessionFormats),
        rates,
      };
    }),
  };
}

// Reads a stored payload back into form values (to refill the form). Unknown or malformed parts are ignored, never trusted.
// Lee un payload guardado y lo vuelve valores del formulario (para rellenar). Lo desconocido o mal formado se ignora.
export type FormDefaults = {
  displayName: string;
  headline: string;
  zone: string;
  practiceStartYear: string;
  cityId: number | null;
  languages: number[];
  phone: string;
  phoneWhatsapp: boolean;
  email: string;
  website: string;
  instagram: string;
  facebook: string;
  tiktok: string;
  youtube: string;
  therapies: TherapyDefaults[];
  currencyOwn: number | null;
  currencyOther: number | null;
};
export type TherapyDefaults = { therapyId: number | null; minutes: string; rateOwn: string; rateOther: string; serviceModes: number[]; sessionFormats: number[] };
export const EMPTY_THERAPY_SLOT: TherapyDefaults = { therapyId: null, minutes: "", rateOwn: "", rateOther: "", serviceModes: [], sessionFormats: [] };
// Always MAX_THERAPIES rows for the form: the stored ones first, then empty rows. / Siempre MAX_THERAPIES filas: primero las guardadas, luego vacías.
export const padTherapies = (rows: TherapyDefaults[]): TherapyDefaults[] =>
  Array.from({ length: MAX_THERAPIES }, (_, index) => rows[index] ?? EMPTY_THERAPY_SLOT);

export const EMPTY_DEFAULTS: FormDefaults = {
  displayName: "", headline: "", zone: "", practiceStartYear: "", cityId: null,
  languages: [], phone: "", phoneWhatsapp: false, email: "", website: "", instagram: "",
  facebook: "", tiktok: "", youtube: "",
  therapies: Array.from({ length: MAX_THERAPIES }, () => EMPTY_THERAPY_SLOT), currencyOwn: null, currencyOther: null,
};

const payloadSchema = z.object({
  display_name: z.string().nullish(),
  headline: z.string().nullish(),
  zone: z.string().nullish(),
  practice_start_year: z.number().int().nullish(),
  location_id: z.number().int().nullish(),
  languages: z.array(z.number().int()).optional(),
  contacts: z.array(z.object({ contact_type_id: z.number().int(), value: z.string(), accepts_whatsapp: z.boolean().optional() })).optional(),
  therapies: z
    .array(z.object({
      therapy_id: z.number().int(),
      session_minutes: z.number().int().nullish(),
      service_modes: z.array(z.number().int()).optional(),
      session_formats: z.array(z.number().int()).optional(),
      rates: z.array(z.object({ rate_audience_id: z.number().int(), amount: z.number(), currency_id: z.number().int() })).optional(),
    }))
    .optional(),
});

export function defaultsFromPayload(payload: unknown, contactTypes: ContactTypeIds, audiences: AudienceIds, base: FormDefaults = EMPTY_DEFAULTS): FormDefaults {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return base;
  const p = parsed.data;
  const contact = (id: number) => p.contacts?.find((entry) => entry.contact_type_id === id);
  const stored = p.therapies ?? [];
  const rateOf = (rates: NonNullable<typeof stored[number]["rates"]> | undefined, audienceId: number) => rates?.find((rate) => rate.rate_audience_id === audienceId);
  const therapies = stored.slice(0, MAX_THERAPIES).map((row) => ({
    therapyId: row.therapy_id,
    minutes: row.session_minutes != null ? String(row.session_minutes) : "",
    rateOwn: rateOf(row.rates, audiences.own) ? String(rateOf(row.rates, audiences.own)?.amount) : "",
    rateOther: rateOf(row.rates, audiences.other) ? String(rateOf(row.rates, audiences.other)?.amount) : "",
    serviceModes: row.service_modes ?? [],
    sessionFormats: row.session_formats ?? [],
  }));
  const currencyFor = (audienceId: number) => stored.flatMap((row) => row.rates ?? []).find((rate) => rate.rate_audience_id === audienceId)?.currency_id ?? null;
  return {
    displayName: p.display_name ?? base.displayName,
    headline: p.headline ?? "",
    zone: p.zone ?? "",
    practiceStartYear: p.practice_start_year != null ? String(p.practice_start_year) : "",
    cityId: p.location_id ?? null,
    languages: p.languages ?? base.languages,
    phone: contact(contactTypes.phone)?.value ?? "",
    phoneWhatsapp: contact(contactTypes.phone)?.accepts_whatsapp ?? false,
    email: contact(contactTypes.email)?.value ?? "",
    website: contact(contactTypes.website)?.value ?? "",
    instagram: contact(contactTypes.instagram)?.value ?? "",
    facebook: contact(contactTypes.facebook)?.value ?? "",
    tiktok: contact(contactTypes.tiktok)?.value ?? "",
    youtube: contact(contactTypes.youtube)?.value ?? "",
    therapies: p.therapies ? padTherapies(therapies) : base.therapies,
    currencyOwn: currencyFor(audiences.own),
    currencyOther: currencyFor(audiences.other),
  };
}

// First message of a failed parse, plus which fields failed (to mark them). / Primer mensaje de un fallo, y qué campos fallaron.
export function firstIssue(error: z.ZodError): { message: string; fields: string[] } {
  return {
    message: error.issues[0]?.message ?? "Revisá los datos.",
    fields: [...new Set(error.issues.map((issue) => String(issue.path[0] ?? "")).filter(Boolean))],
  };
}
