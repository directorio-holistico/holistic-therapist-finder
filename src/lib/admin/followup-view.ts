// Follow-up of therapists who rejected-and-went-quiet or never sent their draft. PURE code (no database), so it can be tested.
// SECURITY: everything here comes from what the therapist typed, so it is only ever shown as text. The phone is text; a WhatsApp
// link exists ONLY when the person marked WhatsApp and the number has the "+" country code (same strict check as the public page).
// Seguimiento de terapeutas con un rechazo sin respuesta o un borrador sin enviar. Código PURO (sin base), para poder probarlo.
// SEGURIDAD: todo viene de lo que escribió el terapeuta, así que solo se muestra como texto. El teléfono es texto; el enlace de
// WhatsApp existe SOLO si la persona marcó WhatsApp y el número lleva el "+" del país (mismo control estricto que la página pública).

import { whatsappHref } from "@/lib/contact-links";
import { contactPhone } from "@/lib/admin/revision-view";

export type RevisionStub = {
  id: string;
  profile_id: string;
  status_id: number;
  created_at: string;
  decided_at: string | null;
  rejection_reason: string | null;
};

export type FollowUpKind = "rejected" | "draft";

export type FollowUpItem = {
  revisionId: string;
  profileId: string;
  kind: FollowUpKind;
  name: string;
  date: string;
  days: number | null;
  reason: string | null;
  profileStatus: string | null;
  phone: { text: string; whatsapp: boolean; whatsappLink: string | null } | null;
  email: string | null;
};

const DAY_MS = 86_400_000;

export function chunksOf<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let start = 0; start < items.length; start += size) out.push(items.slice(start, start + size));
  return out;
}

const timeOf = (iso: string | null): number => (iso === null ? Number.NaN : Date.parse(iso));

// For each profile only its LATEST revision counts. If that one is rejected, the therapist never answered; if it is a draft,
// they started and never sent. A newer revision of any kind means they already reacted.
// De cada perfil cuenta SOLO su última revisión. Si es rechazada, el terapeuta no respondió; si es borrador, empezó y no envió.
// Una revisión posterior de cualquier tipo significa que ya reaccionó.
export function pickFollowUps(
  rows: readonly RevisionStub[],
  ids: { rejected: number; draft: number },
): { rejected: RevisionStub[]; drafts: RevisionStub[] } {
  const latest = new Map<string, RevisionStub>();
  for (const row of rows) {
    const current = latest.get(row.profile_id);
    if (!current || timeOf(row.created_at) > timeOf(current.created_at)) latest.set(row.profile_id, row);
  }
  const rejected: RevisionStub[] = [];
  const drafts: RevisionStub[] = [];
  for (const row of latest.values()) {
    if (row.status_id === ids.rejected) rejected.push(row);
    else if (row.status_id === ids.draft) drafts.push(row);
  }
  const key = (row: RevisionStub) => {
    const t = timeOf(row.decided_at ?? row.created_at);
    return Number.isNaN(t) ? Number.POSITIVE_INFINITY : t;
  };
  rejected.sort((a, b) => key(a) - key(b)); // the oldest first / los más viejos primero
  drafts.sort((a, b) => timeOf(a.created_at) - timeOf(b.created_at) || 0);
  return { rejected, drafts };
}

// Whole days since a moment (never negative), or null if the date cannot be read.
// Días completos desde un momento (nunca negativo), o null si la fecha no se puede leer.
export function daysSince(iso: string | null, nowMs: number): number | null {
  const t = timeOf(iso);
  if (Number.isNaN(t)) return null;
  return Math.max(0, Math.floor((nowMs - t) / DAY_MS));
}

export function elapsedLabel(days: number | null): string {
  if (days === null) return "fecha desconocida";
  if (days === 0) return "hoy";
  return days === 1 ? "hace 1 día" : `hace ${days} días`;
}

const clean = (value: string, max: number): string => value.replace(/[\p{Cc}\p{Cf}]/gu, "").trim().slice(0, max);

export function displayNameOf(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null || !("display_name" in payload)) return null;
  const value = payload.display_name;
  if (typeof value !== "string") return null;
  const text = clean(value, 120);
  return text === "" ? null : text;
}

export function phoneOf(payload: unknown, contactTypeCodes: ReadonlyMap<number, string>): FollowUpItem["phone"] {
  const found = contactPhone(payload, contactTypeCodes);
  if (!found) return null;
  return { text: found.text, whatsapp: found.whatsapp, whatsappLink: found.whatsapp ? whatsappHref(found.text) : null };
}

export function toFollowUpItem(input: {
  stub: RevisionStub;
  kind: FollowUpKind;
  payload: unknown;
  profileDisplayName: string | null;
  personName: string | null;
  email: string | null;
  profileStatusCode: string | null;
  contactTypeCodes: ReadonlyMap<number, string>;
  nowMs: number;
}): FollowUpItem {
  const { stub, kind } = input;
  const date = kind === "rejected" ? (stub.decided_at ?? stub.created_at) : stub.created_at;
  const profileName = input.profileDisplayName === null ? null : clean(input.profileDisplayName, 120);
  const personName = input.personName === null ? null : clean(input.personName, 120);
  const email = input.email === null ? null : clean(input.email, 160);
  return {
    revisionId: stub.id,
    profileId: stub.profile_id,
    kind,
    name: displayNameOf(input.payload) ?? (profileName || null) ?? (personName || null) ?? "Sin nombre",
    date,
    days: daysSince(date, input.nowMs),
    reason: kind === "rejected" ? stub.rejection_reason : null,
    profileStatus: input.profileStatusCode,
    phone: phoneOf(input.payload, input.contactTypeCodes),
    email: email === "" ? null : email,
  };
}
