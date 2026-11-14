// Public profile page data: one row of the view public_profile_detail (the database decides that only published profiles
// are visible, and that no phone and no mail are in it). Everything that comes from the database is re-checked here
// before it reaches the page: links are rebuilt or dropped, odd JSON gives an empty list.
// Datos de la página pública del perfil: una fila de la vista public_profile_detail (la base decide que solo se vean los
// perfiles publicados y que no lleve teléfono ni mail). Todo lo que viene de la base se revisa de nuevo acá antes de
// llegar a la página: los enlaces se rearman o se descartan, un JSON raro da una lista vacía.

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { instagramIsValid } from "@/lib/profile-form";
import type { Database } from "@/lib/supabase/database.types";
import { parseRatesFrom, type RateFrom } from "@/lib/search";

type Client = SupabaseClient<Database>;

export type ProfileLinkKind = "website" | "instagram" | "facebook" | "tiktok" | "youtube";
export type ProfileLink = { kind: ProfileLinkKind; href: string; text: string };

export type TherapyDetail = {
  therapyId: number;
  name: string;
  sessionMinutes: number | null;
  serviceModes: string[];
  sessionFormats: string[];
  rates: RateFrom[];
};

export type ProfileDetail = {
  profileId: string;
  displayName: string;
  headline: string | null;
  place: string;
  countryIso: string | null;
  photoPath: string | null;
  isPinned: boolean;
  practiceStartYear: number | null;
  languages: string[];
  ratesConfirmedAt: string | null;
  ratesCurrent: boolean;
  therapies: TherapyDetail[];
  links: ProfileLink[];
};

// Only the columns the page uses; the real row type of the view is assignable to this.
// Solo las columnas que usa la página; el tipo real de la fila de la vista es asignable a este.
export type DetailRow = {
  profile_id?: string | null;
  display_name?: string | null;
  photo_path?: string | null;
  headline?: string | null;
  city_name?: string | null;
  region_name?: string | null;
  country_name?: string | null;
  country_iso?: string | null;
  languages?: string[] | null;
  rates_confirmed_at?: string | null;
  rates_current?: boolean | null;
  is_pinned?: boolean | null;
  practice_start_year?: number | null;
  website?: string | null;
  instagram?: string | null;
  facebook?: string | null;
  tiktok?: string | null;
  youtube?: string | null;
  therapies_detail?: unknown;
};

const therapySchema = z.object({
  therapy_id: z.number().int(),
  name: z.string().min(1),
  session_minutes: z.number().int().nullable().optional(),
  service_modes: z.array(z.string()),
  session_formats: z.array(z.string()),
  rates: z.unknown(),
});

export function parseTherapies(value: unknown): TherapyDetail[] {
  const parsed = z.array(therapySchema).safeParse(value);
  if (!parsed.success) return [];
  return parsed.data
    .map((item) => ({
      therapyId: item.therapy_id,
      name: item.name,
      sessionMinutes: item.session_minutes ?? null,
      serviceModes: item.service_modes,
      sessionFormats: item.session_formats,
      // same shape as the search card but a list: [{ audience, amount, currency }]
      rates: Array.isArray(item.rates) ? parseRatesList(item.rates) : [],
    }))
    .sort((a, b) => a.name.localeCompare(b.name, "es") || a.therapyId - b.therapyId);
}

const rateItemSchema = z.object({
  audience: z.string().min(1),
  amount: z.coerce.number().finite(),
  currency: z.string().min(1).max(8),
});

function parseRatesList(items: unknown[]): RateFrom[] {
  const list = items.flatMap((item) => {
    const parsed = rateItemSchema.safeParse(item);
    return parsed.success ? [parsed.data] : [];
  });
  // reuse the card's ordering (own country first): { audience: { amount, currency } }
  return parseRatesFrom(Object.fromEntries(list.map((rate) => [rate.audience, { amount: rate.amount, currency: rate.currency }])));
}

// A link from the database is shown only if it is a real http(s) address. Social links must also belong to the expected site.
// Un enlace de la base se muestra solo si es una dirección http(s) real. Los de redes además deben ser del sitio esperado.
export function safeHttpUrl(value: string | null | undefined): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" || url.protocol === "http:" ? url : null;
  } catch {
    return null;
  }
}

const SOCIAL_DOMAINS: Record<"facebook" | "tiktok" | "youtube", string[]> = {
  facebook: ["facebook.com", "fb.com"],
  tiktok: ["tiktok.com"],
  youtube: ["youtube.com"],
};

function belongsTo(url: URL, domains: string[]): boolean {
  const host = url.hostname.toLowerCase();
  return url.protocol === "https:" && domains.some((domain) => host === domain || host.endsWith(`.${domain}`));
}

export function buildLinks(row: Pick<DetailRow, "website" | "instagram" | "facebook" | "tiktok" | "youtube">): ProfileLink[] {
  const links: ProfileLink[] = [];

  const site = safeHttpUrl(row.website);
  if (site) links.push({ kind: "website", href: site.href, text: site.hostname.replace(/^www\./, "") });

  const handle = row.instagram?.trim().toLowerCase() ?? "";
  if (handle !== "" && instagramIsValid(handle)) {
    links.push({ kind: "instagram", href: `https://www.instagram.com/${handle}`, text: `@${handle}` });
  }

  for (const kind of ["facebook", "tiktok", "youtube"] as const) {
    const url = safeHttpUrl(row[kind]);
    if (url && belongsTo(url, SOCIAL_DOMAINS[kind])) {
      links.push({ kind, href: url.href, text: url.hostname.replace(/^www\./, "") + (url.pathname === "/" ? "" : url.pathname.replace(/\/$/, "")) });
    }
  }
  return links;
}

export function toProfileDetail(row: DetailRow): ProfileDetail | null {
  if (!row.profile_id || !row.display_name) return null;
  const place = [row.city_name, row.region_name, row.country_name].filter((part): part is string => Boolean(part)).join(", ");
  return {
    profileId: row.profile_id,
    displayName: row.display_name,
    headline: row.headline ?? null,
    place,
    countryIso: row.country_iso ?? null,
    photoPath: row.photo_path ?? null,
    isPinned: row.is_pinned === true,
    practiceStartYear: row.practice_start_year ?? null,
    languages: row.languages ?? [],
    ratesConfirmedAt: row.rates_confirmed_at ?? null,
    ratesCurrent: row.rates_current === true,
    therapies: parseTherapies(row.therapies_detail),
    links: buildLinks(row),
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// null = it does not exist or it is not public (the same answer for both: nobody can tell them apart).
// null = no existe o no es público (la misma respuesta para los dos: nadie puede distinguirlos).
export async function loadPublicProfile(client: Client, id: string): Promise<ProfileDetail | null> {
  if (!UUID.test(id)) return null;
  const { data, error } = await client.from("public_profile_detail").select("*").eq("profile_id", id).limit(1);
  if (error) throw new Error(`Profile read failed / No se pudo leer el perfil: ${error.message}`);
  const row = data?.[0];
  return row ? toProfileDetail(row) : null;
}
