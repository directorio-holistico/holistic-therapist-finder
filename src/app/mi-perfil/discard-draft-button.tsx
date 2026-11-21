"use client";

import { useActionState } from "react";
import { discardDraft, type DiscardState } from "./discard-draft-action";

// "Descartar borrador": asks first, because it cannot be undone. The published profile and every photo stay as they are.
// "Descartar borrador": pregunta antes, porque no se puede deshacer. El perfil publicado y todas las fotos quedan como están.

const INITIAL: DiscardState = { status: "idle", message: "" };

export function DiscardDraftButton() {
  const [state, action, pending] = useActionState(discardDraft, INITIAL);
  return (
    <form
      action={action}
      onSubmit={(event) => {
        if (!window.confirm("¿Descartar los cambios guardados como borrador? No se puede deshacer. Tu perfil publicado no se modifica.")) event.preventDefault();
      }}
    >
      <button type="submit" disabled={pending} className="inline-flex min-h-11 items-center rounded-full border border-tinta px-5 font-medium text-tinta hover:bg-fondo focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60">
        {pending ? "Descartando…" : "Descartar borrador"}
      </button>
      {state.status === "error" && <p role="alert" className="mt-2 text-sm font-medium text-peligro-texto">{state.message}</p>}
    </form>
  );
}
