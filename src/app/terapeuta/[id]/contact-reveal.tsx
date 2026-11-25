"use client";

// "Ver contacto": loads Cloudflare Turnstile only when the person asks (the widget in "interaction-only" mode shows a check only
// when it doubts), sends the token to /api/reveal and shows the phone and the mail. Nothing is stored in the browser.
// "Ver contacto": carga Cloudflare Turnstile solo cuando la persona lo pide (el widget en modo "interaction-only" muestra una
// comprobación solo cuando duda), manda el token a /api/reveal y muestra el teléfono y el mail. No se guarda nada en el navegador.

import { useEffect, useRef, useState } from "react";
import { emailHref, labelContactType, phoneHref, WHATSAPP_GREETING, whatsappHref } from "@/lib/contact-links";
import { SocialIcon } from "@/components/social-icon";
import { loadTurnstile } from "@/lib/turnstile-client";

// Small line icons; the text label stays for screen readers. / Íconos de línea; el texto queda para lectores de pantalla.
function LineIcon({ children }: { children: React.ReactNode }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" className="shrink-0 text-acento">
      {children}
    </svg>
  );
}
const MailIcon = () => (<LineIcon><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" /></LineIcon>);
const PhoneIcon = () => (<LineIcon><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z" /></LineIcon>);

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
          <p className="text-tinta">Este terapeuta no publicó teléfono ni mail. Podés usar sus redes o su sitio web.</p>
        ) : (
          <ul className="list-none space-y-2 p-0 text-tinta">
            {contacts.map((contact) => {
              const href = contact.type === "phone" ? phoneHref(contact.value) : contact.type === "email" ? emailHref(contact.value) : null;
              const whatsapp = contact.type === "phone" && contact.whatsapp ? whatsappHref(contact.value, WHATSAPP_GREETING) : null;
              return (
                <li key={`${contact.type}-${contact.value}`} className="flex flex-col items-center gap-2 sm:items-start">
                  {whatsapp && (
                    <a
                      className="inline-flex min-h-11 items-center gap-2 rounded-full bg-boton px-6 text-sm font-semibold text-boton-texto hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
                      href={whatsapp}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <SocialIcon kind="whatsapp" size={18} />
                      Escribir por WhatsApp
                    </a>
                  )}
                  <span className="inline-flex items-center gap-2">
                    {contact.type === "email" ? <MailIcon /> : <PhoneIcon />}
                    <span className="sr-only">{labelContactType(contact.type)}: </span>
                    {href ? <a className="underline" href={href}>{contact.value}</a> : <span>{contact.value}</span>}
                  </span>
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
        className="min-h-10 rounded-full bg-boton px-6 text-sm font-semibold text-boton-texto hover:opacity-90 disabled:opacity-60 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
      >
        {busy ? "Verificando…" : "Ver contacto"}
      </button>
      <div ref={container} className="mt-2" />
      <p role="status" className="mt-2 text-sm text-apagado">{message}</p>
    </div>
  );
}
