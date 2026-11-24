// The optional message the administrator leaves when approving a revision. Empty means "no message". The database checks it again
// (1..1000 characters); this only gives a clear answer before the call.
// El mensaje opcional que deja el administrador al aprobar una revisión. Vacío significa "sin mensaje". La base lo vuelve a
// comprobar (1..1000 caracteres); esto solo da una respuesta clara antes de la llamada.

export const APPROVAL_NOTE_MAX = 1000;

export type ApprovalNoteResult = { ok: true; value: string | null } | { ok: false; message: string };

export function readApprovalNote(raw: FormDataEntryValue | null): ApprovalNoteResult {
  if (raw === null) return { ok: true, value: null };
  if (typeof raw !== "string") return { ok: false, message: "El mensaje no es válido." };
  const text = raw.trim();
  if (text === "") return { ok: true, value: null };
  // The database counts characters (code points), not UTF-16 units. / La base cuenta caracteres, no unidades UTF-16.
  if (Array.from(text).length > APPROVAL_NOTE_MAX) return { ok: false, message: `El mensaje admite hasta ${APPROVAL_NOTE_MAX} caracteres.` };
  return { ok: true, value: text };
}
