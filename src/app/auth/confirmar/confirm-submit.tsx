"use client";

// The button of the confirmation page. The email link can be used only ONCE: a second press (slow connection, double tap) would
// arrive with a spent token and send the person to an "expired link" error. After the first press the form is locked and says so.
// El botón de la página de confirmación. El enlace del mail se puede usar UNA sola vez: una segunda pulsación (conexión lenta,
// doble toque) llegaría con el token gastado y mandaría a la persona a un error de "enlace vencido". Tras la primera pulsación
// el formulario se bloquea y lo avisa.

import { useEffect, useState } from "react";

type Props = { tokenHash: string; type: string; next: string };

export function ConfirmSubmit({ tokenHash, type, next }: Props) {
  const [sent, setSent] = useState(false);

  // coming back with the browser's back button must not leave the button locked / volver con "atrás" no debe dejar el botón bloqueado
  useEffect(() => {
    const unlock = (event: PageTransitionEvent) => {
      if (event.persisted) setSent(false);
    };
    window.addEventListener("pageshow", unlock);
    return () => window.removeEventListener("pageshow", unlock);
  }, []);

  return (
    <form
      action="/auth/verificar"
      method="post"
      className="mt-6"
      onSubmit={(event) => {
        if (sent) {
          event.preventDefault();
          return;
        }
        setSent(true);
      }}
    >
      <input type="hidden" name="token_hash" value={tokenHash} />
      <input type="hidden" name="type" value={type} />
      <input type="hidden" name="next" value={next} />
      <button
        type="submit"
        disabled={sent}
        className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60"
      >
        {sent ? "Entrando…" : "Entrar a mi cuenta"}
      </button>
      {sent && (
        <p role="status" className="mt-3 text-apagado">
          Entrando, un momento. No toques el botón de nuevo ni recargues la página.
        </p>
      )}
    </form>
  );
}
