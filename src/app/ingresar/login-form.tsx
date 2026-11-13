"use client";

import { useActionState } from "react";
import { sendLoginLink, type LoginState } from "./actions";

const INITIAL: LoginState = { status: "idle", message: "" };

export function LoginForm() {
  const [state, action, pending] = useActionState(sendLoginLink, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <label htmlFor="email" className="font-medium text-zinc-900 dark:text-zinc-100">Tu mail</label>
      <input
        id="email"
        name="email"
        type="email"
        autoComplete="email"
        inputMode="email"
        required
        maxLength={254}
        aria-describedby="email-help"
        aria-invalid={state.status === "error"}
        className="rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100"
      />
      <p id="email-help" className="text-sm text-zinc-600 dark:text-zinc-400">Sin contraseña: te mandamos un enlace de un solo uso.</p>
      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900"
      >
        {pending ? "Enviando…" : "Enviarme el enlace"}
      </button>
      <p role="status" aria-live="polite" className={state.status === "error" ? "text-red-700 dark:text-red-400" : "text-zinc-800 dark:text-zinc-200"}>
        {state.message}
      </p>
    </form>
  );
}
