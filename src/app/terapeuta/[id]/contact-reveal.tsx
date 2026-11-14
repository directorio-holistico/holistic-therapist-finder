"use client";

// "Ver contacto": loads Cloudflare Turnstile only when the person asks (the widget in "interaction-only" mode shows a check only
// when it doubts), sends the token to /api/reveal and shows the phone and the mail. Nothing is stored in the browser.
// "Ver contacto": carga Cloudflare Turnstile solo cuando la persona lo pide (el widget en modo "interaction-only" muestra una
// comprobación solo cuando duda), manda el token a /api/reveal y muestra el teléfono y el mail. No se guarda nada en el navegador.

import { useEffect, useRef, useState } from "react";
import { emailHref, labelContactType, phoneHref, whatsappHref } from "@/lib/contact-links";
import { loadTurnstile } from "@/lib/turnstile-client";

type Contact = { type: string; value: string; whatsapp: boolean };
const GENERIC_ERROR = "No pudimos mostrar el contacto. Probá de nuevo en unos minutos.";

type Props = { profileId: string; siteKey: string };

export function ContactReveal({ profileId, siteKey }: Props) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [contacts, setContacts] = useState<Contact[] | null>(null);
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
      const response = await fetch("/api/reveal", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ profileId, token }),
      });
      const data = (await response.json().catch(() => null)) as { contacts?: Contact[]; error?: string } | null;
      if (response.ok && data?.contacts) {
        removeWidget();
        setContacts(data.contacts);
        setMessage(null);
        setBusy(false);
        return;
      }
      fail(data?.error ?? GENERIC_ERROR);
    } catch {
      fail(GENERIC_ERROR);
    }
  }

  async function onClick() {
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

  if (contacts !== null) {
    return (
      <div>
        {contacts.length === 0 ? (
          <p className="text-zinc-800 dark:text-zinc-200">Este terapeuta no publicó teléfono ni mail. Podés usar sus redes o su sitio web.</p>
        ) : (
          <ul className="list-none p-0 text-zinc-800 dark:text-zinc-200">
            {contacts.map((contact) => {
              const href = contact.type === "phone" ? phoneHref(contact.value) : contact.type === "email" ? emailHref(contact.value) : null;
              const whatsapp = contact.type === "phone" && contact.whatsapp ? whatsappHref(contact.value) : null;
              return (
                <li key={`${contact.type}-${contact.value}`}>
                  {labelContactType(contact.type)}:{" "}
                  {href ? <a className="underline" href={href}>{contact.value}</a> : <span>{contact.value}</span>}
                  {whatsapp && (
                    <>
                      {" · "}
                      <a className="underline" href={whatsapp} target="_blank" rel="noopener noreferrer">WhatsApp</a>
                    </>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    );
  }

  return (
    <div>
      <button
        type="button"
        onClick={() => void onClick()}
        disabled={busy}
        className="rounded-md bg-zinc-900 px-4 py-2 text-base font-medium text-white hover:bg-zinc-700 disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
      >
        {busy ? "Verificando…" : "Ver contacto"}
      </button>
      <div ref={container} className="mt-2" />
      <p role="status" className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">{message}</p>
    </div>
  );
}
