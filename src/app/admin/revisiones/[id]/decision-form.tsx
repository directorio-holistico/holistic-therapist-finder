"use client";

import { useActionState, useState } from "react";
import { APPROVAL_NOTE_MAX } from "@/lib/admin/approval-note";
import { approveRevision, rejectRevision, type DecisionState } from "./actions";

const INITIAL: DecisionState = { status: "idle", message: "" };
const FIELD = "min-h-11 w-full rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";
const LABEL = "font-medium text-tinta";

export function DecisionForms({ revisionId, canApprove, whyNot, linksToCheck, suggestedReason }: {
  revisionId: string; canApprove: boolean; whyNot: string | null; linksToCheck: number; suggestedReason: string;
}) {
  const [approveState, approve, approving] = useActionState(approveRevision, INITIAL);
  const [rejectState, reject, rejecting] = useActionState(rejectRevision, INITIAL);
  const busy = approving || rejecting;
  // The approve button stays off until the links are confirmed. The server action checks it again (this only guides the click).
  // El botón de aprobar queda apagado hasta confirmar los enlaces. La acción del servidor lo vuelve a revisar (esto solo guía el clic).
  const [linksChecked, setLinksChecked] = useState(false);
  const needsLinksCheck = linksToCheck > 0 && !linksChecked;

  return (
    <div className="mt-6 grid gap-6">
      <form action={approve} className="grid gap-3 rounded-xl border border-linea bg-superficie p-5">
        <h2 className="font-display text-xl font-semibold text-tinta">Aprobar</h2>
        <input type="hidden" name="revisionId" value={revisionId} />
        {linksToCheck > 0 && (
          <label className="flex items-start gap-3 text-tinta">
            <input type="checkbox" name="linksChecked" checked={linksChecked} onChange={(event) => setLinksChecked(event.target.checked)} className="mt-1 h-5 w-5 accent-acento" />
            <span>Revisé los enlaces públicos (web y redes): son del terapeuta y no son engañosos.</span>
          </label>
        )}
        <div className="grid gap-1">
          <label htmlFor="note" className={LABEL}>Mensaje para el terapeuta (opcional)</label>
          <p id="note-help" className="text-sm text-apagado">Lo ve en su perfil y puede eliminarlo. Dejalo vacío si no querés enviar nada.</p>
          <textarea id="note" name="note" rows={5} maxLength={APPROVAL_NOTE_MAX} aria-describedby="note-help" className={FIELD} />
        </div>
        {whyNot && <p className="text-sm text-aviso-texto">{whyNot}</p>}
        {approveState.status === "error" && <p role="alert" className="text-peligro-texto">{approveState.message}</p>}
        <button type="submit" disabled={busy || !canApprove || needsLinksCheck}
          className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50">
          {approving ? "Aprobando…" : "Aprobar y publicar"}
        </button>
      </form>

      <form action={reject} className="grid gap-3 rounded-xl border border-linea bg-superficie p-5">
        <h2 className="font-display text-xl font-semibold text-tinta">Rechazar</h2>
        <input type="hidden" name="revisionId" value={revisionId} />
        <div className="grid gap-1">
          <label htmlFor="reason" className={LABEL}>Motivo (lo ve el terapeuta)</label>
          <textarea id="reason" name="reason" rows={suggestedReason === "" ? 4 : 8} maxLength={1000} required defaultValue={suggestedReason} className={FIELD} />
        </div>
        {rejectState.status === "error" && <p role="alert" className="text-peligro-texto">{rejectState.message}</p>}
        <button type="submit" disabled={busy}
          className="inline-flex min-h-11 items-center justify-center rounded-full border border-tinta px-5 font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50">
          {rejecting ? "Rechazando…" : "Rechazar"}
        </button>
      </form>
    </div>
  );
}
