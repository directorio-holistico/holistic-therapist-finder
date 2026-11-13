// Rules of the therapist sign-up form, shared by the server action and the tests. Pure code, no database.
// The database has the final say (register_therapist); this only gives clear messages before calling it.
// Reglas del formulario de alta del terapeuta, compartidas por la acción del servidor y las pruebas. Código puro.
// La base tiene la última palabra (register_therapist); esto solo da mensajes claros antes de llamarla.

import { z } from "zod";
import { LEGAL_VERSIONS } from "@/lib/legal/versions";

export const FULL_NAME_MAX = 120;

export const registrationSchema = z.object({
  fullName: z
    .string()
    .transform((value) => value.trim().replace(/\s+/g, " "))
    .pipe(z.string().min(1, "Escribí tu nombre completo.").max(FULL_NAME_MAX, `Máximo ${FULL_NAME_MAX} caracteres.`)),
  terms: z.literal(true, { error: "Tenés que aceptar los términos." }),
  privacy: z.literal(true, { error: "Tenés que aceptar la política de privacidad." }),
  legalDeclaration: z.literal(true, { error: "Tenés que aceptar la declaración legal." }),
  offers: z.boolean(),
});

export type RegistrationInput = z.infer<typeof registrationSchema>;

// HTML checkboxes send "on" when checked and nothing when not. / Las casillas HTML mandan "on" si están marcadas y nada si no.
export function readRegistrationForm(formData: FormData) {
  const checked = (name: string) => formData.get(name) === "on";
  return registrationSchema.safeParse({
    fullName: String(formData.get("fullName") ?? ""),
    terms: checked("terms"),
    privacy: checked("privacy"),
    legalDeclaration: checked("legalDeclaration"),
    offers: checked("offers"),
  });
}

// {document code: version} for register_therapist. The optional offers consent is included ONLY when checked.
// {código de documento: versión} para register_therapist. El consentimiento opcional de ofertas va SOLO si se marcó.
export function buildAcceptances(input: Pick<RegistrationInput, "offers">): Record<string, string> {
  const acceptances: Record<string, string> = {
    terms: LEGAL_VERSIONS.terms,
    privacy: LEGAL_VERSIONS.privacy,
    legal_declaration: LEGAL_VERSIONS.legal_declaration,
  };
  if (input.offers) acceptances.offers_consent = LEGAL_VERSIONS.offers_consent;
  return acceptances;
}

// Postgres error code -> what to tell the person. Anything else is a generic message (the detail goes to the log).
// Código de error de Postgres -> qué decirle a la persona. Cualquier otro es un mensaje genérico (el detalle va al log).
export function registrationErrorMessage(code: string | undefined): string {
  switch (code) {
    case "42501":
      return "Primero tenés que ingresar con el enlace de tu mail y tenerlo verificado.";
    case "22023":
      return "Revisá los datos: algo no es válido.";
    default:
      return "No pudimos completar el alta ahora. Probá de nuevo en unos minutos.";
  }
}
