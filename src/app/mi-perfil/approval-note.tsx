"use client";

import { useActionState } from "react";
import { deleteApprovalNote, type ApprovalNoteState } from "./approval-note-action";

const INITIAL: ApprovalNoteState = { status: "idle", message: "" };
const SECONDARY = "inline-flex min-h-11 items-center rounded-full border border-tinta px-5 font-medium text-tinta hover:bg-fondo focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";

export function ApprovalNote({ revisionId, text }: { revisionId: string; text: string }) {
  const [state, action, pending] = useActionState(deleteApprovalNote, INITIAL);
  return (
    <section aria-labelledby="mensaje-equipo" className="mt-6 rounded-xl border border-ok-borde bg-ok-fondo p-5">
      <h2 id="mensaje-equipo" className="font-display text-xl font-semibold text-ok-texto">Mensaje del equipo</h2>
      {/* React escapes the text; the line breaks of the message are kept. / React escapa el texto; se conservan los saltos de línea. */}
      <p className="mt-3 whitespace-pre-line text-tinta">{text}</p>
      <form
        action={action}
        onSubmit={(event) => {
          if (!window.confirm("¿Eliminar este mensaje? No se puede deshacer.")) event.preventDefault();
        }}
        className="mt-4 grid gap-2"
      >
        <input type="hidden" name="revisionId" value={revisionId} />
        <div><button type="submit" disabled={pending} className={SECONDARY}>{pending ? "Eliminando…" : "Eliminar mensaje"}</button></div>
        {state.status === "error" && <p role="alert" className="text-sm font-medium text-peligro-texto">{state.message}</p>}
      </form>
    </section>
  );
}
