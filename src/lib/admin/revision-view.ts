// Turns the raw payload of a revision into something an administrator can read and check. PURE code (no database).
// SECURITY: a revision payload is written by the therapist through the API, so NOTHING in it is trusted. Text is only ever
// shown as text; a value becomes a clickable link ONLY if it passes the same strict format the database enforces
// (https links to the expected sites). The phone and the e-mail are not shown at all: only that they exist.
// Convierte el payload crudo de una revisión en algo que el administrador pueda leer y revisar. Código PURO (sin base).
// SEGURIDAD: el payload lo escribe el terapeuta por la API, así que NADA es de confianza. El texto se muestra siempre como
// texto; un valor es un enlace clickeable SOLO si cumple el mismo formato estricto que exige la base (https a los sitios
// esperados). El teléfono y el mail no se muestran: solo si existen.

import { z } from "zod";
import { isPendingPhotoPath, photoChangeOf, type PhotoChange } from "@/lib/photo-rules";
import { instagramIsValid, socialLinkIsValid } from "@/lib/profile-form";

export type ViewLookups = {
  therapies: ReadonlyMap<number, string>;
  inactiveTherapies?: ReadonlySet<number>; // therapies that exist but are hidden / terapias que existen pero están ocultas
  currencies: ReadonlyMap<number, string>;
  audiences: ReadonlyMap<number, string>;
  languages: ReadonlyMap<number, string>;
  serviceModes: ReadonlyMap<number, string>;
  sessionFormats: ReadonlyMap<number, string>;
  contactTypes: ReadonlyMap<number, string>;
};

export type LinkKind = "website" | "instagram" | "facebook" | "tiktok" | "youtube";
export type ContactLink = { kind: LinkKind; value: string; href: string | null };
export type RateView = { audience: string; amount: number; currency: string };
export type TherapyView = { name: string; description: string | null; minutes: number | null; serviceModes: string[]; sessionFormats: string[]; rates: RateView[] };

export type RevisionView = {
  displayName: string | null;
  headline: string | null;
  about: string | null;
  zone: string | null;
  practiceStartYear: number | null;
  locationId: number | null;
  languages: string[];
  therapies: TherapyView[];
  photo: PhotoChange;
  hasPhone: boolean;
  phoneWhatsapp: boolean;
  hasEmail: boolean;
  links: ContactLink[];
};

export const payloadSchema = z.looseObject({
  display_name: z.string().nullish(),
  headline: z.string().nullish(),
  about: z.string().nullish(),
  zone: z.string().nullish(),
  practice_start_year: z.number().int().nullish(),
  location_id: z.number().int().nullish(),
  photo_path: z.string().nullable().optional(),
  languages: z.array(z.number().int()).optional(),
  contacts: z.array(z.looseObject({ contact_type_id: z.number().int(), value: z.string(), accepts_whatsapp: z.boolean().optional() })).optional(),
  therapies: z
    .array(z.looseObject({
      therapy_id: z.number().int(),
      description: z.string().nullish(),
      session_minutes: z.number().int().nullish(),
      service_modes: z.array(z.number().int()).optional(),
      session_formats: z.array(z.number().int()).optional(),
      rates: z.array(z.looseObject({ rate_audience_id: z.number().int(), amount: z.number(), currency_id: z.number().int() })).optional(),
    }))
    .optional(),
});

const LINK_KINDS: readonly string[] = ["website", "instagram", "facebook", "tiktok", "youtube"];
const isLinkKind = (code: string): code is LinkKind => LINK_KINDS.includes(code);

// The address a link would open, or null when the value does not have the strict expected format.
// La dirección que abriría un enlace, o null si el valor no tiene el formato estricto esperado.
export function safeHref(kind: LinkKind, value: string): string | null {
  if (kind === "website") {
    if (!/^https?:\/\/[^ ]+$/.test(value)) return null;
    try {
      const url = new URL(value);
      return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
    } catch {
      return null;
    }
  }
  if (kind === "instagram") return instagramIsValid(value) ? `https://www.instagram.com/${value}` : null;
  return socialLinkIsValid(kind, value) ? value : null;
}

const names = (ids: readonly number[] | undefined, map: ReadonlyMap<number, string>): string[] => (ids ?? []).map((id) => map.get(id) ?? `#${id}`);

// null when the payload is not an object of the expected shape (the page then says so instead of guessing).
// null si el payload no es un objeto con la forma esperada (la página lo dice en vez de adivinar).
export function describeRevision(payload: unknown, lookups: ViewLookups): RevisionView | null {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return null;
  const p = parsed.data;
  const contacts = p.contacts ?? [];
  const phone = contacts.find((contact) => lookups.contactTypes.get(contact.contact_type_id) === "phone");
  const links: ContactLink[] = [];
  for (const contact of contacts) {
    const code = lookups.contactTypes.get(contact.contact_type_id) ?? "";
    if (isLinkKind(code)) links.push({ kind: code, value: contact.value, href: safeHref(code, contact.value) });
  }
  return {
    displayName: p.display_name ?? null,
    headline: p.headline ?? null,
    about: p.about ?? null,
    zone: p.zone ?? null,
    practiceStartYear: p.practice_start_year ?? null,
    locationId: p.location_id ?? null,
    languages: names(p.languages, lookups.languages),
    therapies: (p.therapies ?? []).map((therapy) => ({
      name: lookups.therapies.get(therapy.therapy_id) ?? `#${therapy.therapy_id}`,
      description: therapy.description ?? null,
      minutes: therapy.session_minutes ?? null,
      serviceModes: names(therapy.service_modes, lookups.serviceModes),
      sessionFormats: names(therapy.session_formats, lookups.sessionFormats),
      rates: (therapy.rates ?? []).map((rate) => ({
        audience: lookups.audiences.get(rate.rate_audience_id) ?? `#${rate.rate_audience_id}`,
        amount: rate.amount,
        currency: lookups.currencies.get(rate.currency_id) ?? `#${rate.currency_id}`,
      })),
    })),
    photo: photoChangeOf(p),
    hasPhone: phone !== undefined,
    phoneWhatsapp: phone?.accepts_whatsapp ?? false,
    hasEmail: contacts.some((contact) => lookups.contactTypes.get(contact.contact_type_id) === "email"),
    links,
  };
}

// The phone as TEXT, for the administrator to write to the person (never a link: a number without country code could reach a stranger).
// Control and invisible characters are removed and the length is capped like the form does; React shows it as plain text.
// El teléfono como TEXTO, para que el administrador le escriba a la persona (nunca un enlace: un número sin código de país podría llegar a un extraño).
// Se quitan los caracteres de control e invisibles y se limita el largo como el formulario; React lo muestra como texto plano.
export function contactPhone(payload: unknown, contactTypeCodes: ReadonlyMap<number, string>): { text: string; whatsapp: boolean } | null {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return null;
  const found = (parsed.data.contacts ?? []).find((contact) => contactTypeCodes.get(contact.contact_type_id) === "phone");
  if (!found) return null;
  const text = found.value.replace(/[\p{Cc}\p{Cf}]/gu, "").trim().slice(0, 40);
  return text === "" ? null : { text, whatsapp: found.accepts_whatsapp === true };
}

// Only what the decision rules need (no names): is there a city, and which public links must the administrator check?
// Solo lo que necesitan las reglas de la decisión (sin nombres): ¿hay ciudad? y ¿qué enlaces públicos debe revisar?
export function decisionFacts(payload: unknown, contactTypeCodes: ReadonlyMap<number, string>, profileId?: string): { hasCity: boolean; linksToCheck: number; photoOk: boolean } | null {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return null;
  const links = (parsed.data.contacts ?? []).filter((contact) => isLinkKind(contactTypeCodes.get(contact.contact_type_id) ?? "")).length;
  // a proposed photo must be a pending file of the profile / la foto propuesta tiene que ser un archivo pendiente del perfil
  const change = photoChangeOf(parsed.data);
  const photoOk = change.kind !== "set" || (profileId !== undefined && isPendingPhotoPath(change.path, profileId));
  return { hasCity: parsed.data.location_id != null, linksToCheck: links, photoOk };
}

// ---- What changed compared with the last approved version / Qué cambió respecto de la última versión aprobada ----
// The live profile only changes through an approved revision, so the last approved payload is what the public sees today.
// El perfil vigente solo cambia con una revisión aprobada, así que el último payload aprobado es lo que el público ve hoy.
export type FieldKey = "photo" | "displayName" | "headline" | "about" | "location" | "zone" | "practiceStartYear" | "languages" | "therapies" | "phone" | "email" | "links";

export const FIELD_NAMES: Record<FieldKey, string> = {
  photo: "Foto", displayName: "Nombre público", headline: "Presentación", about: "Sobre mí", location: "Ciudad", zone: "Zona o barrio",
  practiceStartYear: "Empezó como terapeuta", languages: "Idiomas", therapies: "Terapias", phone: "Teléfono", email: "Mail", links: "Enlaces públicos",
};

export type RevisionChanges =
  | { kind: "first" } // no approved version before: everything is new / no hay versión aprobada previa: todo es nuevo
  | { kind: "unavailable" } // the previous content cannot be read: no comparison / no se puede leer lo anterior: sin comparación
  | { kind: "diff"; changed: ReadonlySet<FieldKey> };

// Phone and e-mail are compared but NEVER shown: only "changed" is reported. / El teléfono y el mail se comparan pero NUNCA se muestran.
function rawContact(payload: unknown, lookups: ViewLookups, code: string): string {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return "";
  const found = (parsed.data.contacts ?? []).find((contact) => lookups.contactTypes.get(contact.contact_type_id) === code);
  return found ? `${found.value}|${found.accepts_whatsapp === true}` : "";
}

const same = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b);
const sorted = (values: readonly string[]): string[] => [...values].sort();

export function changedFields(payload: unknown, previousPayload: unknown | null, lookups: ViewLookups): RevisionChanges | null {
  const current = describeRevision(payload, lookups);
  if (!current) return null;
  if (previousPayload === null) return { kind: "first" };
  const before = describeRevision(previousPayload, lookups);
  if (!before) return { kind: "unavailable" };
  const changed = new Set<FieldKey>();
  const check = (key: FieldKey, differs: boolean) => { if (differs) changed.add(key); };
  check("photo", current.photo.kind !== "none");
  check("displayName", !same(current.displayName, before.displayName));
  check("headline", !same(current.headline, before.headline));
  check("about", !same(current.about, before.about));
  check("location", !same(current.locationId, before.locationId));
  check("zone", !same(current.zone, before.zone));
  check("practiceStartYear", !same(current.practiceStartYear, before.practiceStartYear));
  check("languages", !same(sorted(current.languages), sorted(before.languages)));
  check("therapies", !same(sorted(current.therapies.map((t) => JSON.stringify(t))), sorted(before.therapies.map((t) => JSON.stringify(t)))));
  check("phone", rawContact(payload, lookups, "phone") !== rawContact(previousPayload, lookups, "phone"));
  check("email", rawContact(payload, lookups, "email") !== rawContact(previousPayload, lookups, "email"));
  check("links", !same(sorted(current.links.map((l) => `${l.kind}|${l.value}`)), sorted(before.links.map((l) => `${l.kind}|${l.value}`))));
  return { kind: "diff", changed };
}
