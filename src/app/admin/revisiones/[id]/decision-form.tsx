"use client";

import { useActionState, useState } from "react";
import { approveRevision, rejectRevision, type DecisionState } from "./actions";

const INITIAL: DecisionState = { status: "idle", message: "" };
const FIELD = "w-full rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";
const LABEL = "font-medium text-zinc-900 dark:text-zinc-100";

export function DecisionForms({ revisionId, canApprove, whyNot, linksToCheck }: {
  revisionId: string; canApprove: boolean; whyNot: string | null; linksToCheck: number;
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
      <form action={approve} className="grid gap-3 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
        <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Aprobar</h2>
        <input type="hidden" name="revisionId" value={revisionId} />
        {linksToCheck > 0 && (
          <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
            <input type="checkbox" name="linksChecked" checked={linksChecked} onChange={(event) => setLinksChecked(event.target.checked)} className="mt-1 h-5 w-5" />
            <span>Revisé los enlaces públicos (web y redes): son del terapeuta y no son engañosos.</span>
          </label>
        )}
        {whyNot && <p className="text-sm text-amber-900">{whyNot}</p>}
        {approveState.status === "error" && <p role="alert" className="text-red-800">{approveState.message}</p>}
        <button type="submit" disabled={busy || !canApprove || needsLinksCheck}
          className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900">
          {approving ? "Aprobando…" : "Aprobar y publicar"}
        </button>
      </form>

      <form action={reject} className="grid gap-3 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
        <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Rechazar</h2>
        <input type="hidden" name="revisionId" value={revisionId} />
        <div className="grid gap-1">
          <label htmlFor="reason" className={LABEL}>Motivo (lo ve el terapeuta)</label>
          <textarea id="reason" name="reason" rows={4} maxLength={1000} required className={FIELD} />
        </div>
        {rejectState.status === "error" && <p role="alert" className="text-red-800">{rejectState.message}</p>}
        <button type="submit" disabled={busy}
          className="rounded-md border border-zinc-400 px-4 py-3 font-medium text-zinc-900 disabled:opacity-50 dark:text-zinc-100">
          {rejecting ? "Rechazando…" : "Rechazar"}
        </button>
      </form>
    </div>
  );
}
