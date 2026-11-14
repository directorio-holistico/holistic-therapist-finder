"use client";

// "Denunciar este perfil": a closed block with the reason (required), a free detail and an optional mail. Turnstile loads only
// when the person sends the form. A report never takes a profile down by itself: a person reviews it.
// "Denunciar este perfil": un bloque cerrado con el motivo (obligatorio), un detalle libre y un mail opcional. Turnstile se carga solo
// al enviar el formulario. Una denuncia nunca baja un perfil por sí sola: la revisa una persona.

import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import { REPORT_DETAILS_MAX, REPORT_EMAIL_MAX, REPORT_REASONS, REPORT_SUCCESS_MESSAGE } from "@/lib/report-reasons";
import { loadTurnstile } from "@/lib/turnstile-client";

const GENERIC_ERROR = "No pudimos enviar la denuncia. Probá de nuevo en unos minutos.";

type Props = { profileId: string; siteKey: string };

export function ReportForm({ profileId, siteKey }: Props) {
  const ids = useId();
  const [reason, setReason] = useState("");
  const [details, setDetails] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const widgetId = useRef<string | null>(null);

  function removeWidget() {
    if (widgetId.current && window.turnstile) window.turnstile.remove(widgetId.current);
    widgetId.current = null;
  }

  useEffect(() => removeWidget, []);

  function fail(text: string) {
    removeWidget();
    setMessage(text);
    setBusy(false);
  }

  async function send(token: string) {
    try {
      const response = await fetch("/api/report", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ profileId, reason, details, email, token }),
      });
      const data = (await response.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (response.ok && data?.ok) {
        removeWidget();
        setSent(true);
        setMessage(null);
        setBusy(false);
        return;
      }
      fail(data?.error ?? GENERIC_ERROR);
    } catch {
      fail(GENERIC_ERROR);
    }
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    if (!reason) {
      setMessage("Elegí un motivo.");
      return;
    }
    setBusy(true);
    setMessage(null);
    removeWidget();
    try {
      await loadTurnstile();
    } catch {
      fail("No se pudo cargar la verificación. Revisá tu conexión y probá de nuevo.");
      return;
    }
    if (!window.turnstile || !container.current) return fail(GENERIC_ERROR);
    widgetId.current = window.turnstile.render(container.current, {
      sitekey: siteKey,
      appearance: "interaction-only",
      language: "es",
      callback: (token: string) => void send(token),
      "error-callback": () => fail("La verificación falló. Probá de nuevo."),
      "expired-callback": () => fail("La verificación venció. Probá de nuevo."),
    });
  }

  if (sent) {
    return <p role="status" className="text-zinc-800 dark:text-zinc-200">{REPORT_SUCCESS_MESSAGE}</p>;
  }

  const field = "mt-1 w-full rounded-md border border-zinc-400 bg-white px-3 py-2 text-base text-zinc-900 dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-100";

  return (
    <details className="text-zinc-800 dark:text-zinc-200">
      <summary className="cursor-pointer text-sm underline">Denunciar este perfil</summary>
      <form onSubmit={(event) => void onSubmit(event)} className="mt-3 grid max-w-xl gap-4">
        <p className="text-sm text-zinc-700 dark:text-zinc-300">
          Usalo si el perfil promete curas, tiene información falsa o algo no está bien. No hace falta que des tu nombre. Una persona
          revisa cada denuncia; el perfil no se baja de forma automática.
        </p>
        <div>
          <label htmlFor={`${ids}-reason`} className="block text-sm font-medium">Motivo</label>
          <select id={`${ids}-reason`} required value={reason} onChange={(event) => setReason(event.target.value)} className={field}>
            <option value="">Elegí un motivo</option>
            {REPORT_REASONS.map((item) => (
              <option key={item.code} value={item.code}>{item.label}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`${ids}-details`} className="block text-sm font-medium">Detalle (opcional)</label>
          <textarea
            id={`${ids}-details`}
            rows={4}
            maxLength={REPORT_DETAILS_MAX}
            value={details}
            onChange={(event) => setDetails(event.target.value)}
            className={field}
          />
          <p className="mt-1 text-xs text-zinc-700 dark:text-zinc-300">Hasta {REPORT_DETAILS_MAX} caracteres. No escribas datos de salud.</p>
        </div>
        <div>
          <label htmlFor={`${ids}-email`} className="block text-sm font-medium">Tu mail (opcional)</label>
          <input
            id={`${ids}-email`}
            type="email"
            autoComplete="email"
            maxLength={REPORT_EMAIL_MAX}
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            aria-describedby={`${ids}-email-help`}
            className={field}
          />
          <p id={`${ids}-email-help`} className="mt-1 text-xs text-zinc-700 dark:text-zinc-300">
            Solo lo ve quien revisa las denuncias, para pedirte más datos. Si el motivo es un mail o un dato de contacto
            incorrecto, escribí acá el correcto.
          </p>
        </div>
        <div>
          <button
            type="submit"
            disabled={busy}
            className="rounded-md bg-zinc-900 px-4 py-2 text-base font-medium text-white hover:bg-zinc-700 disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
          >
            {busy ? "Enviando…" : "Enviar denuncia"}
          </button>
          <div ref={container} className="mt-2" />
          <p role="status" className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">{message}</p>
        </div>
      </form>
    </details>
  );
}
