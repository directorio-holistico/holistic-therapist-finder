"use client";

import { useActionState } from "react";
import { sendLoginLink, sendPasswordReset, signInWithPassword, type LoginState } from "./actions";

const INITIAL: LoginState = { status: "idle", message: "" };
const FIELD = "rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";
const BUTTON = "rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900";

function Message({ state }: { state: LoginState }) {
  return (
    <p role="status" aria-live="polite" className={state.status === "error" ? "text-red-700 dark:text-red-400" : "text-zinc-800 dark:text-zinc-200"}>
      {state.message}
    </p>
  );
}

function EmailField({ state, help }: { state: LoginState; help?: string }) {
  return (
    <>
      <label htmlFor="email" className="font-medium text-zinc-900 dark:text-zinc-100">Tu mail</label>
      <input
        id="email"
        name="email"
        type="email"
        autoComplete="email"
        inputMode="email"
        required
        maxLength={254}
        aria-describedby={help ? "email-help" : undefined}
        aria-invalid={state.status === "error"}
        className={FIELD}
      />
      {help && <p id="email-help" className="text-sm text-zinc-600 dark:text-zinc-400">{help}</p>}
    </>
  );
}

// The normal login: mail + password. / El ingreso normal: mail + contraseña.
export function PasswordLoginForm() {
  const [state, action, pending] = useActionState(signInWithPassword, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <EmailField state={state} />
      <label htmlFor="password" className="font-medium text-zinc-900 dark:text-zinc-100">Tu contraseña</label>
      <input id="password" name="password" type="password" autoComplete="current-password" required maxLength={200} className={FIELD} />
      <button type="submit" disabled={pending} className={BUTTON}>{pending ? "Ingresando…" : "Ingresar"}</button>
      <Message state={state} />
    </form>
  );
}

// First time: an email link creates the account. / Primera vez: un enlace al mail crea la cuenta.
export function FirstTimeForm() {
  const [state, action, pending] = useActionState(sendLoginLink, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <EmailField state={state} help="Te mandamos un enlace de un solo uso. Al abrirlo vas a elegir tu contraseña." />
      <button type="submit" disabled={pending} className={BUTTON}>{pending ? "Enviando…" : "Enviarme el enlace"}</button>
      <Message state={state} />
    </form>
  );
}

// Forgot the password: an email link to choose a new one. / Olvidé la contraseña: un enlace al mail para elegir otra.
export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState(sendPasswordReset, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <EmailField state={state} help="Te mandamos un enlace de un solo uso para elegir una contraseña nueva." />
      <button type="submit" disabled={pending} className={BUTTON}>{pending ? "Enviando…" : "Enviarme el enlace"}</button>
      <Message state={state} />
    </form>
  );
}
