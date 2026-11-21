"use client";

import { useActionState } from "react";
import { PASSWORD_MIN_LENGTH } from "@/lib/auth/password";
import { setPassword, type PasswordState } from "./actions";

const INITIAL: PasswordState = { status: "idle", message: "" };
const FIELD = "min-h-11 rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";

export function PasswordForm() {
  const [state, action, pending] = useActionState(setPassword, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <label htmlFor="password" className="font-medium text-tinta">Contraseña nueva</label>
      <input id="password" name="password" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN_LENGTH} aria-describedby="password-help" className={FIELD} />
      <p id="password-help" className="text-sm text-apagado">Al menos {PASSWORD_MIN_LENGTH} caracteres. Una frase larga es más segura que una palabra con números.</p>
      <label htmlFor="confirm" className="font-medium text-tinta">Repetí la contraseña</label>
      <input id="confirm" name="confirm" type="password" autoComplete="new-password" required className={FIELD} />
      <button type="submit" disabled={pending} className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60">
        {pending ? "Guardando…" : "Guardar contraseña"}
      </button>
      <p role="alert" aria-live="polite" className="text-peligro-texto">{state.status === "error" ? state.message : ""}</p>
    </form>
  );
}
