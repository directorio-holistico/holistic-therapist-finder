// Data in a revision that the database would refuse when approving, found BEFORE the administrator clicks "Aprobar".
// PURE code (no database). Each message is written for the THERAPIST (it is also offered as the rejection reason), so the person
// knows what to fix. The database stays the judge: it re-checks everything inside approve_revision; this only explains early.
// Datos de una revisión que la base rechazaría al aprobar, detectados ANTES de que el administrador apriete "Aprobar".
// Código PURO (sin base). Cada mensaje está escrito para el TERAPEUTA (también se ofrece como motivo de rechazo), así la persona
// sabe qué corregir. La base sigue siendo la que decide: revisa todo de nuevo dentro de approve_revision; esto solo explica antes.

import { payloadSchema, safeHref, type LinkKind, type ViewLookups } from "@/lib/admin/revision-view";
import { containsContactData } from "@/lib/profile-form";

export type ProblemContext = {
  // Is the chosen city active? null = unknown (not read) or no city. / ¿La ciudad elegida está activa? null = no se leyó o no hay ciudad.
  locationActive: boolean | null;
  // The therapy the therapist asked to add (column suggested_therapy), if any. / La terapia que el terapeuta pidió agregar, si hay.
  suggestedTherapy?: string | null;
};

// Same limits as the database (CHECK constraints and validate_profile_texts). / Mismos límites que la base.
const MAX_HEADLINE = 280;
const MAX_ABOUT = 1500;
const MAX_DESCRIPTION = 200;
const PHONE_CHARS = /^\+?[0-9 ()-]+$/;
const EMAIL_SHAPE = /^[^@ ]+@[^@ ]+\.[^@ ]+$/;

const LINK_NAMES: Record<LinkKind, string> = { website: "la página web", instagram: "Instagram", facebook: "Facebook", tiktok: "TikTok", youtube: "YouTube" };
const isLinkKind = (code: string): code is LinkKind => Object.prototype.hasOwnProperty.call(LINK_NAMES, code);

export function revisionProblems(payload: unknown, lookups: ViewLookups, context: ProblemContext): string[] {
  const parsed = payloadSchema.safeParse(payload);
  if (!parsed.success) return [];
  const p = parsed.data;
  const found = new Set<string>(); // a Set: the same problem in two therapies is told once / un Set: el mismo problema en dos terapias se cuenta una vez

  if (p.location_id != null && context.locationActive === false) {
    found.add("La ciudad que elegiste ya no está disponible. Elegí otra, o pedinos que la agreguemos.");
  }
  if ((p.headline ?? "").trim().length > MAX_HEADLINE) found.add(`La frase de presentación es demasiado larga (máximo ${MAX_HEADLINE} caracteres).`);
  const about = (p.about ?? "").trim();
  if (about.length > MAX_ABOUT) found.add(`«Sobre mí» es demasiado largo (máximo ${MAX_ABOUT} caracteres).`);
  if (about !== "" && containsContactData(about)) {
    found.add("En «Sobre mí» no se pueden incluir enlaces, mails, @usuarios ni teléfonos: para eso están los campos de contacto.");
  }
  // A profile with no therapy would be published empty: the database does not forbid it, so it is stopped here.
  // Un perfil sin terapias se publicaría vacío: la base no lo prohíbe, por eso se frena acá.
  if (p.therapies !== undefined && p.therapies.length === 0) {
    const asked = context.suggestedTherapy?.trim();
    found.add(
      asked
        ? `Pediste agregar «${asked}». La estamos evaluando; si la agregamos, te avisamos para que la elijas en tu perfil.`
        : "No elegiste ninguna terapia. Elegí al menos una.",
    );
  }
  for (const id of p.languages ?? []) {
    if (!lookups.languages.has(id)) found.add("Hay un idioma elegido que ya no está disponible. Revisá los idiomas.");
  }

  for (const therapy of p.therapies ?? []) {
    const name = lookups.therapies.get(therapy.therapy_id);
    if (name === undefined || lookups.inactiveTherapies?.has(therapy.therapy_id)) {
      found.add(`La terapia «${name ?? "desconocida"}» no está disponible en el directorio por ahora. Quitala de tu perfil.`);
    }
    const description = (therapy.description ?? "").trim();
    const label = name ?? "una terapia";
    if (description.length > MAX_DESCRIPTION) found.add(`La descripción de «${label}» es demasiado larga (máximo ${MAX_DESCRIPTION} caracteres).`);
    if (description !== "" && containsContactData(description)) {
      found.add(`En la descripción de «${label}» no se pueden incluir enlaces, mails, @usuarios ni teléfonos.`);
    }
    for (const id of therapy.service_modes ?? []) {
      if (!lookups.serviceModes.has(id)) found.add(`Hay una modalidad de atención de «${label}» que ya no está disponible. Revisala.`);
    }
    for (const id of therapy.session_formats ?? []) {
      if (!lookups.sessionFormats.has(id)) found.add(`Hay un formato de sesión de «${label}» que ya no está disponible. Revisalo.`);
    }
    for (const rate of therapy.rates ?? []) {
      if (!lookups.audiences.has(rate.rate_audience_id) || !lookups.currencies.has(rate.currency_id)) {
        found.add(`Hay una tarifa de «${label}» con una moneda o un tipo de paciente que ya no está disponible. Revisala.`);
      }
    }
  }

  for (const contact of p.contacts ?? []) {
    const code = lookups.contactTypes.get(contact.contact_type_id);
    if (code === undefined) {
      found.add("Hay un tipo de contacto que ya no está disponible. Revisá tus datos de contacto.");
    } else if (code === "phone") {
      const digits = contact.value.replace(/[^0-9]/g, "").length;
      if (!PHONE_CHARS.test(contact.value) || digits < 6 || digits > 15) {
        found.add("El teléfono no tiene un formato válido: solo números, espacios, paréntesis y guiones, con el código de país.");
      }
    } else if (code === "email") {
      if (contact.value !== contact.value.toLowerCase() || !EMAIL_SHAPE.test(contact.value)) {
        found.add("El mail debe estar en minúsculas y tener el formato nombre@dominio.com.");
      }
    } else if (isLinkKind(code) && safeHref(code, contact.value) === null) {
      found.add(`El enlace de ${LINK_NAMES[code]} no tiene un formato válido. Revisalo.`);
    }
  }
  return [...found];
}

const REASON_MAX = 1000; // the rejection reason accepts up to 1000 characters / el motivo admite hasta 1000 caracteres

// A rejection reason for the therapist built from the problems (never longer than the limit). Empty when there are none.
// Un motivo de rechazo para el terapeuta armado con los problemas (nunca más largo que el límite). Vacío si no hay ninguno.
export function suggestedReason(problems: readonly string[]): string {
  if (problems.length === 0) return "";
  const head = "No pudimos publicar tu perfil por lo siguiente:";
  const tail = "Corregilo desde «Editar perfil» y volvé a enviarlo.";
  let text = head;
  for (const problem of problems) {
    const next = `${text}\n- ${problem}`;
    if (next.length + 1 + tail.length > REASON_MAX) break;
    text = next;
  }
  return `${text}\n${tail}`;
}
