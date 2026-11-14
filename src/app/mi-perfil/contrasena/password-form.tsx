"use client";

import { useActionState } from "react";
import { PASSWORD_MIN_LENGTH } from "@/lib/auth/password";
import { setPassword, type PasswordState } from "./actions";

const INITIAL: PasswordState = { status: "idle", message: "" };
const FIELD = "rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";

export function PasswordForm() {
  const [state, action, pending] = useActionState(setPassword, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <label htmlFor="password" className="font-medium text-zinc-900 dark:text-zinc-100">Contraseña nueva</label>
      <input id="password" name="password" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN_LENGTH} aria-describedby="password-help" className={FIELD} />
      <p id="password-help" className="text-sm text-zinc-600 dark:text-zinc-400">Al menos {PASSWORD_MIN_LENGTH} caracteres. Una frase larga es más segura que una palabra con números.</p>
      <label htmlFor="confirm" className="font-medium text-zinc-900 dark:text-zinc-100">Repetí la contraseña</label>
      <input id="confirm" name="confirm" type="password" autoComplete="new-password" required className={FIELD} />
      <button type="submit" disabled={pending} className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900">
        {pending ? "Guardando…" : "Guardar contraseña"}
      </button>
      <p role="alert" aria-live="polite" className="text-red-700 dark:text-red-400">{state.status === "error" ? state.message : ""}</p>
    </form>
  );
}
