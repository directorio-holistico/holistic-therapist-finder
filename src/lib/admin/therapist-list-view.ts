// Admin list of therapists. PURE code (no database), so it can be tested.
// SECURITY: names and phones were typed by the therapist, so they are only ever shown as text. The phone number is NEVER shown here:
// the only thing built from it is a WhatsApp link, and only when the person marked WhatsApp and the number has the "+" country code
// (same strict check as the public page). The account e-mail is shown ONLY for people who registered and never saved anything
// (state "unpublished"): for them it is the only way to reach the person. For every other state it is not even kept in the row.
// Lista de terapeutas para administración. Código PURO (sin base), para poder probarlo.
// SEGURIDAD: nombres y teléfonos los escribió el terapeuta, así que solo se muestran como texto. El número de teléfono NUNCA se muestra
// acá: lo único que se arma con él es un enlace de WhatsApp, y solo si la persona marcó WhatsApp y el número lleva el "+" del país
// (mismo control estricto que la página pública). El mail de la cuenta se muestra SOLO de quien se registró y nunca guardó nada
// (estado "unpublished"): para esa persona es la única forma de contactarla. En los demás estados ni siquiera queda en la fila.

import { emailHref, whatsappHref } from "@/lib/contact-links";

export type TherapistState = "pending" | "published" | "rejected" | "draft" | "unpublished" | "paused" | "suspended";
export type RatesState = "current" | "expired" | "none";

// Order and titles of the containers on the page. / Orden y títulos de los contenedores de la página.
export const STATE_ORDER: readonly TherapistState[] = ["pending", "published", "rejected", "draft", "unpublished", "paused", "suspended"];
export const STATE_TITLES: Record<TherapistState, string> = {
  pending: "En espera de revisión",
  published: "Publicados",
  rejected: "Rechazados",
  draft: "Borradores",
  unpublished: "Sin publicar",
  paused: "Pausados",
  suspended: "Suspendidos",
};

export type ProfileStub = {
  id: string;
  person_id: string;
  display_name: string | null;
  status_id: number;
  location_id: number | null;
  rates_confirmed_at: string | null;
};
export type PersonStub = { id: string; full_name: string | null; email: string | null; created_at: string; erased_at: string | null };
export type ContactStub = { profile_id: string; contact_type_id: number; value: string; accepts_whatsapp: boolean };
export type RevisionLite = { profile_id: string; status_id: number; created_at: string };

export type TherapistRow = {
  profileId: string;
  name: string;
  countryIso: string | null;
  countryName: string | null;
  registeredAt: string;
  ratesConfirmedAt: string | null;
  rates: RatesState;
  state: TherapistState;
  note: string | null;
  whatsappLink: string | null;
  hasPhone: boolean;
  email: string | null; // only for "unpublished" / solo para "unpublished"
};

const timeOf = (iso: string | null): number => (iso === null ? Number.NaN : Date.parse(iso));
const clean = (value: string, max: number): string => value.replace(/[\p{Cc}\p{Cf}]/gu, "").trim().slice(0, max);

// For each profile, the status id of its LATEST revision, ignoring discarded ones (a discarded draft is as if it never existed).
// De cada perfil, el id de estado de su ÚLTIMA revisión, sin contar las descartadas (un borrador descartado es como si no existiera).
export function latestRevisionStatus(rows: readonly RevisionLite[], discardedId: number | null): Map<string, number> {
  const latest = new Map<string, RevisionLite>();
  for (const row of rows) {
    if (discardedId !== null && row.status_id === discardedId) continue;
    const current = latest.get(row.profile_id);
    if (!current || timeOf(row.created_at) > timeOf(current.created_at)) latest.set(row.profile_id, row);
  }
  return new Map([...latest].map(([profileId, row]) => [profileId, row.status_id]));
}

// One container per therapist. The profile status decides first; a published profile stays "Publicado" even when it has a change
// on its way (that is only written as a note). / Un contenedor por terapeuta. Decide primero el estado del perfil; un perfil
// publicado sigue "Publicado" aunque tenga un cambio en camino (eso solo va como nota).
export function stateOf(profileCode: string | null, revisionCode: string | null): { state: TherapistState; note: string | null } | null {
  if (profileCode === "erased" || profileCode === null) return null; // not listed / no se lista
  if (profileCode === "suspended") return { state: "suspended", note: null };
  if (profileCode === "paused") return { state: "paused", note: null };
  if (profileCode === "published") {
    const note = revisionCode === "pending_review" ? "Tiene un cambio en revisión" : revisionCode === "rejected" ? "Su último cambio fue rechazado" : revisionCode === "draft" ? "Tiene un borrador de cambio" : null;
    return { state: "published", note };
  }
  if (revisionCode === "pending_review") return { state: "pending", note: null };
  if (revisionCode === "rejected") return { state: "rejected", note: null };
  if (revisionCode === "draft") return { state: "draft", note: null };
  return { state: "unpublished", note: null };
}

// Same rule as the database: "current" while the confirmation date is within `months` months. / Misma regla que la base: "al día" mientras la fecha esté dentro de `months` meses.
export function ratesStateOf(confirmedAt: string | null, months: number, nowMs: number): RatesState {
  const t = timeOf(confirmedAt);
  if (Number.isNaN(t)) return "none";
  const limit = new Date(t);
  limit.setUTCMonth(limit.getUTCMonth() + months);
  return nowMs <= limit.getTime() ? "current" : "expired";
}

// Walks up to the root of the tree (the country) from a location id. Three levels at most; a loop or a gap gives null.
// Sube hasta la raíz del árbol (el país) desde un id de ubicación. Tres niveles como máximo; un ciclo o un hueco da null.
export function countryIdOf(locationId: number | null, parents: ReadonlyMap<number, number | null>): number | null {
  let current = locationId;
  for (let level = 0; level < 3 && current !== null; level += 1) {
    if (!parents.has(current)) return null;
    const parent: number | null = parents.get(current) ?? null;
    if (parent === null) return current;
    current = parent;
  }
  return null;
}

// The WhatsApp link of a profile: the first phone that is marked as WhatsApp AND passes the strict check. Never the number itself.
// El enlace de WhatsApp de un perfil: el primer teléfono marcado como WhatsApp Y que pasa el control estricto. Nunca el número.
export function whatsappOf(contacts: readonly ContactStub[], phoneTypeId: number | null): { link: string | null; hasPhone: boolean } {
  if (phoneTypeId === null) return { link: null, hasPhone: false };
  const phones = contacts.filter((contact) => contact.contact_type_id === phoneTypeId && clean(contact.value, 40) !== "");
  for (const phone of phones) {
    if (!phone.accepts_whatsapp) continue;
    const link = whatsappHref(clean(phone.value, 40));
    if (link) return { link, hasPhone: true };
  }
  return { link: null, hasPhone: phones.length > 0 };
}

export function toTherapistRow(input: {
  profile: ProfileStub;
  person: PersonStub | undefined;
  profileCode: string | null;
  revisionCode: string | null;
  countryIso: string | null;
  countryName: string | null;
  contacts: readonly ContactStub[];
  phoneTypeId: number | null;
  months: number;
  nowMs: number;
}): TherapistRow | null {
  const { profile, person } = input;
  if (!person || person.erased_at !== null) return null; // erased people are not listed / a quien se dio de baja no se lo lista
  const decided = stateOf(input.profileCode, input.revisionCode);
  if (!decided) return null;
  const profileName = profile.display_name === null ? "" : clean(profile.display_name, 120);
  const personName = person.full_name === null ? "" : clean(person.full_name, 120);
  const whatsapp = whatsappOf(input.contacts, input.phoneTypeId);
  const accountEmail = person.email === null ? "" : clean(person.email, 160);
  return {
    profileId: profile.id,
    name: profileName || personName || "Sin nombre",
    countryIso: input.countryIso,
    countryName: input.countryName,
    registeredAt: person.created_at,
    ratesConfirmedAt: profile.rates_confirmed_at,
    rates: ratesStateOf(profile.rates_confirmed_at, input.months, input.nowMs),
    state: decided.state,
    note: decided.note,
    whatsappLink: whatsapp.link,
    hasPhone: whatsapp.hasPhone,
    email: decided.state === "unpublished" && emailHref(accountEmail) !== null ? accountEmail : null,
  };
}

// Fixed message for people who registered and never filled in their profile. No promises, no health claims, nothing about money.
// Mensaje fijo para quien se registró y nunca completó su perfil. Sin promesas, sin afirmaciones de salud, nada de dinero.
export const NUDGE_SUBJECT = "Tu perfil en Faro Holístico quedó a medio camino";
export function nudgeBody(siteUrl: string): string {
  return [
    "Hola,",
    "",
    "Te escribo desde Faro Holístico, el directorio gratuito de terapeutas holísticos. Vi que te registraste, pero todavía no cargaste los datos de tu perfil, por eso aún no aparecés en las búsquedas.",
    "",
    `Completarlo lleva pocos minutos: ingresás con este mismo mail en ${siteUrl}/ingresar, entrás a "Mi perfil" y completás tus terapias, tu ciudad y una forma de contacto. Lo revisamos antes de publicarlo y, una vez aprobado, las personas que busquen podrán encontrarte.`,
    "",
    "Si tenés dudas o algo te frenó, respondé este mail y te ayudo.",
    "",
    "Un abrazo,",
    "Ariel · Faro Holístico",
  ].join("\n");
}

// Gmail "compose" link with the message already written (no dependence on the computer's default mail program); null when the
// address does not pass the check. / Enlace de redacción de Gmail con el mensaje ya escrito (sin depender del programa de correo
// predeterminado de la computadora); null si la dirección no pasa el control.
export function nudgeGmailLink(email: string, siteUrl: string): string | null {
  if (emailHref(email) === null) return null;
  const query = `view=cm&fs=1&to=${encodeURIComponent(email)}&su=${encodeURIComponent(NUDGE_SUBJECT)}&body=${encodeURIComponent(nudgeBody(siteUrl))}`;
  return `https://mail.google.com/mail/?${query}`;
}

// Containers in the fixed order, each sorted by name; empty ones are left out. / Contenedores en orden fijo, cada uno por nombre; los vacíos no van.
export function groupByState(rows: readonly TherapistRow[]): { state: TherapistState; title: string; rows: TherapistRow[] }[] {
  return STATE_ORDER.map((state) => ({
    state,
    title: STATE_TITLES[state],
    rows: rows.filter((row) => row.state === state).sort((a, b) => a.name.localeCompare(b.name, "es")),
  })).filter((group) => group.rows.length > 0);
}
