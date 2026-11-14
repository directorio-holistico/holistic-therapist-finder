"use client";

import { useActionState } from "react";
import { closeReport, reinstateProfile, suspendProfile, type ActionState } from "./actions";

const INITIAL: ActionState = { status: "idle", message: "" };
const FIELD = "w-full rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";
const LABEL = "font-medium text-zinc-900 dark:text-zinc-100";
const BOX = "grid gap-3 rounded-lg border border-zinc-300 p-4 dark:border-zinc-700";
const TITLE = "text-lg font-semibold text-zinc-900 dark:text-zinc-100";

type Props = {
  reportId: number;
  isOpen: boolean;
  profileId: string | null;
  canSuspend: boolean;
  canReinstate: boolean;
};

export function ReportForms({ reportId, isOpen, profileId, canSuspend, canReinstate }: Props) {
  const [closeState, close, closing] = useActionState(closeReport, INITIAL);
  const [suspendState, suspend, suspending] = useActionState(suspendProfile, INITIAL);
  const [reinstateState, reinstate, reinstating] = useActionState(reinstateProfile, INITIAL);
  const busy = closing || suspending || reinstating;

  return (
    <div className="mt-6 grid gap-6">
      {profileId && canSuspend && (
        <form action={suspend} className={BOX}>
          <h2 className={TITLE}>Suspender el perfil</h2>
          <p className="text-sm text-zinc-700 dark:text-zinc-300">
            El perfil deja de ser público ahora mismo y el terapeuta lo ve suspendido. Queda registrado quién lo hizo y por qué.
            Cerrar la denuncia es un paso aparte.
          </p>
          <input type="hidden" name="reportId" value={reportId} />
          <input type="hidden" name="profileId" value={profileId} />
          <div className="grid gap-1">
            <label htmlFor="suspend-reason" className={LABEL}>Motivo (queda en el registro)</label>
            <textarea id="suspend-reason" name="reason" rows={3} maxLength={500} required className={FIELD} />
          </div>
          <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
            <input type="checkbox" name="confirm" required className="mt-1 h-5 w-5" />
            <span>Confirmo que quiero suspender este perfil.</span>
          </label>
          {suspendState.status === "error" && <p role="alert" className="text-red-800">{suspendState.message}</p>}
          <button type="submit" disabled={busy} className="rounded-md bg-red-800 px-4 py-3 font-medium text-white disabled:opacity-50">
            {suspending ? "Suspendiendo…" : "Suspender perfil"}
          </button>
        </form>
      )}

      {profileId && canReinstate && (
        <form action={reinstate} className={BOX}>
          <h2 className={TITLE}>Reponer el perfil</h2>
          <p className="text-sm text-zinc-700 dark:text-zinc-300">
            Si ya fue aprobado antes, vuelve a ser público; si no, queda sin publicar. Queda registrado quién lo hizo y por qué.
          </p>
          <input type="hidden" name="reportId" value={reportId} />
          <input type="hidden" name="profileId" value={profileId} />
          <div className="grid gap-1">
            <label htmlFor="reinstate-reason" className={LABEL}>Motivo (queda en el registro)</label>
            <textarea id="reinstate-reason" name="reason" rows={3} maxLength={1000} required className={FIELD} />
          </div>
          {reinstateState.status === "error" && <p role="alert" className="text-red-800">{reinstateState.message}</p>}
          <button type="submit" disabled={busy} className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900">
            {reinstating ? "Reponiendo…" : "Reponer perfil"}
          </button>
        </form>
      )}

      {isOpen && (
        <form action={close} className={BOX}>
          <h2 className={TITLE}>Cerrar la denuncia</h2>
          <input type="hidden" name="reportId" value={reportId} />
          <div className="grid gap-1">
            <label htmlFor="close-status" className={LABEL}>Resultado</label>
            <select id="close-status" name="status" required defaultValue="" className={FIELD}>
              <option value="" disabled>Elegí cómo se cierra</option>
              <option value="dismissed">Descartada (no hay nada que hacer)</option>
              <option value="resolved">Resuelta (se tomó una medida)</option>
            </select>
          </div>
          <div className="grid gap-1">
            <label htmlFor="close-note" className={LABEL}>Nota de cierre (queda en el registro)</label>
            <textarea id="close-note" name="note" rows={3} maxLength={1000} required className={FIELD} />
          </div>
          {closeState.status === "error" && <p role="alert" className="text-red-800">{closeState.message}</p>}
          <button type="submit" disabled={busy} className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900">
            {closing ? "Cerrando…" : "Cerrar denuncia"}
          </button>
        </form>
      )}
    </div>
  );
}
