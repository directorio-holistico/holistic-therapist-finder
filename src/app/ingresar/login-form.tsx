"use client";

import { useActionState } from "react";
import { sendLoginLink, sendPasswordReset, signInWithPassword, type LoginState } from "./actions";

const INITIAL: LoginState = { status: "idle", message: "" };
const FIELD = "min-h-11 w-full rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento";
const BUTTON = "inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60";

function Message({ state }: { state: LoginState }) {
  return (
    <p role="status" aria-live="polite" className={state.status === "error" ? "text-peligro-texto" : "text-tinta"}>
      {state.message}
    </p>
  );
}

function EmailField({ state, help }: { state: LoginState; help?: string }) {
  return (
    <>
      <label htmlFor="email" className="font-medium text-tinta">Tu mail</label>
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
      {help && <p id="email-help" className="text-sm text-apagado">{help}</p>}
    </>
  );
}

// The normal login: mail + password. / El ingreso normal: mail + contraseña.
export function PasswordLoginForm() {
  const [state, action, pending] = useActionState(signInWithPassword, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-3" noValidate>
      <EmailField state={state} />
      <label htmlFor="password" className="font-medium text-tinta">Tu contraseña</label>
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
