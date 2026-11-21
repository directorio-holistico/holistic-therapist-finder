"use client";

import { useActionState, useState } from "react";
import { closeReport, reinstateProfile, suspendProfile, type ActionState } from "./actions";

const INITIAL: ActionState = { status: "idle", message: "" };
const FIELD = "min-h-11 w-full rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";
const LABEL = "font-medium text-tinta";
const BOX = "grid gap-3 rounded-xl border border-linea bg-superficie p-5";
const TITLE = "font-display text-xl font-semibold text-tinta";

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

  // A button is enabled only when its form is complete (the text counts without spaces at the ends). The server and the database check again.
  // Un botón se habilita solo cuando su formulario está completo (el texto cuenta sin espacios en los extremos). El servidor y la base vuelven a revisar.
  const [suspendReason, setSuspendReason] = useState("");
  const [suspendConfirmed, setSuspendConfirmed] = useState(false);
  const [reinstateReason, setReinstateReason] = useState("");
  const [closeResult, setCloseResult] = useState("");
  const [closeNote, setCloseNote] = useState("");
  const suspendReady = suspendReason.trim().length > 0 && suspendConfirmed;
  const reinstateReady = reinstateReason.trim().length > 0;
  const closeReady = closeResult !== "" && closeNote.trim().length > 0;

  return (
    <div className="mt-6 grid gap-6">
      {profileId && canSuspend && (
        <form action={suspend} className={BOX}>
          <h2 className={TITLE}>Suspender el perfil</h2>
          <p className="text-sm text-apagado">
            El perfil deja de ser público ahora mismo y el terapeuta lo ve suspendido. Queda registrado quién lo hizo y por qué.
            Cerrar la denuncia es un paso aparte.
          </p>
          <input type="hidden" name="reportId" value={reportId} />
          <input type="hidden" name="profileId" value={profileId} />
          <div className="grid gap-1">
            <label htmlFor="suspend-reason" className={LABEL}>Motivo (queda en el registro)</label>
            <textarea id="suspend-reason" name="reason" rows={3} maxLength={500} required value={suspendReason} onChange={(e) => setSuspendReason(e.target.value)} className={FIELD} />
          </div>
          <label className="flex items-start gap-3 text-tinta">
            <input type="checkbox" name="confirm" required checked={suspendConfirmed} onChange={(e) => setSuspendConfirmed(e.target.checked)} className="mt-1 h-5 w-5 accent-acento" />
            <span>Confirmo que quiero suspender este perfil.</span>
          </label>
          {suspendState.status === "error" && <p role="alert" className="text-peligro-texto">{suspendState.message}</p>}
          <button type="submit" disabled={busy || !suspendReady} className="inline-flex min-h-11 items-center justify-center rounded-full bg-peligro-texto px-5 font-medium text-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50">
            {suspending ? "Suspendiendo…" : "Suspender perfil"}
          </button>
        </form>
      )}

      {profileId && canReinstate && (
        <form action={reinstate} className={BOX}>
          <h2 className={TITLE}>Reponer el perfil</h2>
          <p className="text-sm text-apagado">
            Si ya fue aprobado antes, vuelve a ser público; si no, queda sin publicar. Queda registrado quién lo hizo y por qué.
          </p>
          <input type="hidden" name="reportId" value={reportId} />
          <input type="hidden" name="profileId" value={profileId} />
          <div className="grid gap-1">
            <label htmlFor="reinstate-reason" className={LABEL}>Motivo (queda en el registro)</label>
            <textarea id="reinstate-reason" name="reason" rows={3} maxLength={1000} required value={reinstateReason} onChange={(e) => setReinstateReason(e.target.value)} className={FIELD} />
          </div>
          {reinstateState.status === "error" && <p role="alert" className="text-peligro-texto">{reinstateState.message}</p>}
          <button type="submit" disabled={busy || !reinstateReady} className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50">
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
            <select id="close-status" name="status" required value={closeResult} onChange={(e) => setCloseResult(e.target.value)} className={FIELD}>
              <option value="" disabled>Elegí cómo se cierra</option>
              <option value="dismissed">Descartada (no hay nada que hacer)</option>
              <option value="resolved">Resuelta (se tomó una medida)</option>
            </select>
          </div>
          <div className="grid gap-1">
            <label htmlFor="close-note" className={LABEL}>Nota de cierre (queda en el registro)</label>
            <textarea id="close-note" name="note" rows={3} maxLength={1000} required value={closeNote} onChange={(e) => setCloseNote(e.target.value)} className={FIELD} />
          </div>
          {closeState.status === "error" && <p role="alert" className="text-peligro-texto">{closeState.message}</p>}
          <button type="submit" disabled={busy || !closeReady} className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50">
            {closing ? "Cerrando…" : "Cerrar denuncia"}
          </button>
        </form>
      )}
    </div>
  );
}
