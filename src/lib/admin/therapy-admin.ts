// Rules of the admin screen that adds, hides and shows therapies: what the form accepts, how the code is proposed from the name,
// how a therapist's suggestion is split into names, and what each database refusal means. Pure code: no database here.
// The database decides again (admin_add_therapy / admin_set_therapy_active check the administrator and every value).
// Reglas de la pantalla de admin que agrega, oculta y muestra terapias: qué acepta el formulario, cómo se propone el código a
// partir del nombre, cómo se parte la sugerencia de un terapeuta en nombres y qué significa cada rechazo de la base. Código puro:
// acá no hay base. La base vuelve a decidir (admin_add_therapy / admin_set_therapy_active revisan al admin y cada valor).

import { z } from "zod";

export const THERAPY_LIMITS = { name: 120, shortName: 40, code: 60 } as const;
// Same rule as the database function: a letter first, then letters, digits or "_", 2 to 60 characters.
// Misma regla que la función de la base: letra primero, luego letras, dígitos o "_", de 2 a 60 caracteres.
export const THERAPY_CODE_PATTERN = /^[a-z][a-z0-9_]{1,59}$/;
export const SUGGESTIONS_SHOWN = 50;

const collapse = (value: string): string => value.replace(/\s+/g, " ").trim();

// "Coaching transpersonal" -> "coaching_transpersonal". Accents and symbols are dropped; a code never starts with a digit.
// "Coaching transpersonal" -> "coaching_transpersonal". Se sacan tildes y símbolos; un código nunca empieza con un dígito.
export function proposeTherapyCode(name: string): string {
  const base = name
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  const startsWithLetter = base === "" || /^[a-z]/.test(base) ? base : `t_${base}`;
  return startsWithLetter.slice(0, THERAPY_LIMITS.code).replace(/_+$/, "");
}

const addSchema = z.object({
  name: z.string().transform(collapse).pipe(
    z.string().min(1, "Escribí el nombre de la terapia.").max(THERAPY_LIMITS.name, `El nombre admite hasta ${THERAPY_LIMITS.name} caracteres.`),
  ),
  shortName: z.string().transform(collapse).pipe(
    z.string().max(THERAPY_LIMITS.shortName, `El nombre corto admite hasta ${THERAPY_LIMITS.shortName} caracteres.`),
  ).transform((value) => (value === "" ? null : value)),
  code: z.string().transform((value) => value.trim()).pipe(
    z.string().regex(THERAPY_CODE_PATTERN, "El código usa minúsculas sin tildes, números y «_», empieza con una letra y tiene de 2 a 60 caracteres."),
  ),
  active: z.boolean(),
});

export type AddTherapyValues = z.infer<typeof addSchema>;
export type AddTherapyParse = { ok: true; value: AddTherapyValues } | { ok: false; message: string };

// Reads the add form. The checkbox sends "on" only when it is ticked. / Lee el formulario de alta. El tilde manda "on" solo si está marcado.
export function readAddTherapyForm(formData: FormData): AddTherapyParse {
  const text = (key: string): string => {
    const value = formData.get(key);
    return typeof value === "string" ? value : "";
  };
  const parsed = addSchema.safeParse({
    name: text("name"),
    shortName: text("shortName"),
    code: text("code"),
    active: formData.get("active") === "on",
  });
  return parsed.success ? { ok: true, value: parsed.data } : { ok: false, message: parsed.error.issues[0]?.message ?? "Revisá el formulario." };
}

// One message per database refusal; the detail stays in the server log. / Un mensaje por rechazo de la base; el detalle queda en el log.
export function explainTherapyError(error: { code?: string }): string {
  switch (error.code) {
    case "42501": return "No se pudo: no sos administrador.";
    case "23505": return "Ya existe una terapia con ese código o con ese nombre. Revisá la lista.";
    case "22023": return "La base no acepta algún dato del formulario. Revisalo.";
    case "P0002": return "No se encontró esa terapia. Recargá la lista.";
    default: return "No pudimos completar la acción. Probá de nuevo en unos minutos.";
  }
}

// A therapist writes up to 3 names separated by commas; this gives the names one by one, without repeats (accents and capitals ignored).
// Un terapeuta escribe hasta 3 nombres separados por coma; esto da los nombres uno por uno, sin repetidos (sin importar tildes ni mayúsculas).
export function splitSuggestedTherapies(text: string): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const piece of text.split(",")) {
    const name = collapse(piece);
    const key = name.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
    if (name === "" || seen.has(key)) continue;
    seen.add(key);
    names.push(name);
  }
  return names;
}

// The name a "Add" link carries in the address, to pre-fill the form. Never trusted: trimmed and cut to the limit.
// El nombre que lleva en la dirección un enlace "Agregar", para precargar el formulario. Nunca se confía: se recorta y se limita.
export function parseNameParam(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === "string" ? collapse(value).slice(0, THERAPY_LIMITS.name) : "";
}

const REVISION_STATUS_LABELS: Record<string, string> = {
  draft: "Borrador sin enviar",
  pending_review: "Esperando revisión",
  approved: "Aprobada",
  rejected: "Rechazada",
  discarded: "Descartada",
};
export const revisionStatusLabel = (code: string): string => REVISION_STATUS_LABELS[code] ?? code;

// A request can be cleared only when its revision is decided (approved, rejected or discarded); an open one is still being worked on.
// Un pedido se puede borrar solo cuando su revisión está decidida (aprobada, rechazada o descartada); una abierta sigue en trabajo.
export const canDismissSuggestion = (statusCode: string): boolean => ["approved", "rejected", "discarded"].includes(statusCode);

export function explainDismissError(error: { code?: string }): string {
  switch (error.code) {
    case "42501": return "No se pudo: no sos administrador.";
    case "55000": return "Primero decidí la revisión (aprobarla o rechazarla); después podés descartar el pedido.";
    case "P0002": return "Ese pedido ya no existe. Recargá la lista.";
    case "22023": return "Pedido inválido.";
    default: return "No pudimos completar la acción. Probá de nuevo en unos minutos.";
  }
}

export const RESULT_NOTICES: Record<string, string> = {
  agregada: "La terapia quedó agregada.",
  descartada: "El pedido quedó descartado.",
};
