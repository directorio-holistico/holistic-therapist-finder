// Turns the raw payload of a revision into something an administrator can read and check. PURE code (no database).
// SECURITY: a revision payload is written by the therapist through the API, so NOTHING in it is trusted. Text is only ever
// shown as text; a value becomes a clickable link ONLY if it passes the same strict format the database enforces
// (https links to the expected sites). The phone and the e-mail are not shown at all: only that they exist.
// Convierte el payload crudo de una revisión en algo que el administrador pueda leer y revisar. Código PURO (sin base).
// SEGURIDAD: el payload lo escribe el terapeuta por la API, así que NADA es de confianza. El texto se muestra siempre como
// texto; un valor es un enlace clickeable SOLO si cumple el mismo formato estricto que exige la base (https a los sitios
// esperados). El teléfono y el mail no se muestran: solo si existen.

import { z } from "zod";
import { instagramIsValid, socialLinkIsValid } from "@/lib/profile-form";

export type ViewLookups = {
  therapies: ReadonlyMap<number, string>;
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
export type TherapyView = { name: string; minutes: number | null; rates: RateView[] };

export type RevisionView = {
  displayName: string | null;
  headline: string | null;
  zone: string | null;
  practiceStartYear: number | null;
  locationId: number | null;
  languages: string[];
  serviceModes: string[];
  sessionFormats: string[];
  therapies: TherapyView[];
  hasPhone: boolean;
  phoneWhatsapp: boolean;
  hasEmail: boolean;
  links: ContactLink[];
};

const payloadSchema = z.looseObject({
  display_name: z.string().nullish(),
  headline: z.string().nullish(),
  zone: z.string().nullish(),
  practice_start_year: z.number().int().nullish(),
  location_id: z.number().int().nullish(),
  languages: z.array(z.number().int()).optional(),
  service_modes: z.array(z.number().int()).optional(),
  session_formats: z.array(z.number().int()).optional(),
  contacts: z.array(z.looseObject({ contact_type_id: z.number().int(), value: z.string(), accepts_whatsapp: z.boolean().optional() })).optional(),
  therapies: z
    .array(z.looseObject({
      therapy_id: z.number().int(),
      session_minutes: z.number().int().nullish(),
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
    zone: p.zone ?? null,
    practiceStartYear: p.practice_start_year ?? null,
    locationId: p.location_id ?? null,
    languages: names(p.languages, lookups.languages),
    serviceModes: names(p.service_modes, lookups.serviceModes),
    sessionFormats: names(p.session_formats, lookups.sessionFormats),
    therapies: (p.therapies ?? []).map((therapy) => ({
      name: lookups.therapies.get(therapy.therapy_id) ?? `#${therapy.therapy_id}`,
      minutes: therapy.session_minutes ?? null,
      rates: (therapy.rates ?? []).map((rate) => ({
        audience: lookups.audiences.get(rate.rate_audience_id) ?? `#${rate.rate_audience_id}`,
        amount: rate.amount,
        currency: lookups.currencies.get(rate.currency_id) ?? `#${rate.currency_id}`,
      })),
    })),
    hasPhone: phone !== undefined,
    phoneWhatsapp: phone?.accepts_whatsapp ?? false,
    hasEmail: contacts.some((contact) => lookups.contactTypes.get(contact.contact_type_id) === "email"),
    links,
  };
}

// Only what the decision rules need (no names): is there a city, and which public links must the administrator check?
// Solo lo que necesitan las reglas de la decisión (sin nombres): ¿hay ciudad? y ¿qué enlaces públicos debe revisar?
export function decisionFacts(payload: unknown, contactTypeCodes: ReadonlyMap<number, string>): { hasCity: boolean; linksToCheck: number } | null {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return null;
  const links = (parsed.data.contacts ?? []).filter((contact) => isLinkKind(contactTypeCodes.get(contact.contact_type_id) ?? "")).length;
  return { hasCity: parsed.data.location_id != null, linksToCheck: links };
}
