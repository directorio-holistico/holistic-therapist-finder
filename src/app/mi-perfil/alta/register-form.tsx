"use client";

import Link from "next/link";
import { useActionState } from "react";
import { registerTherapist, type RegisterState } from "./actions";

const INITIAL: RegisterState = { status: "idle", message: "" };
const FIELD = "rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100";

export function RegisterForm({ suggestedName }: { suggestedName: string }) {
  const [state, action, pending] = useActionState(registerTherapist, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-4" noValidate>
      <div className="grid gap-1">
        <label htmlFor="fullName" className="font-medium text-zinc-900 dark:text-zinc-100">Tu nombre completo</label>
        <input id="fullName" name="fullName" type="text" autoComplete="name" required maxLength={120}
          defaultValue={suggestedName} aria-describedby="fullName-help" className={FIELD} />
        <p id="fullName-help" className="text-sm text-zinc-600 dark:text-zinc-400">
          Es el nombre de tu cuenta. El nombre que se muestra en el perfil lo elegís después.
        </p>
      </div>

      <fieldset className="grid gap-3">
        <legend className="font-medium text-zinc-900 dark:text-zinc-100">Para continuar necesitamos que aceptes</legend>
        <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="terms" required className="mt-1 h-5 w-5" />
          <span>Leí y acepto los <Link className="underline" href="/legal/terminos" target="_blank">términos y condiciones</Link>.</span>
        </label>
        <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="privacy" required className="mt-1 h-5 w-5" />
          <span>Leí la <Link className="underline" href="/legal/privacidad" target="_blank">política de privacidad</Link> y estoy de acuerdo.</span>
        </label>
        <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="legalDeclaration" required className="mt-1 h-5 w-5" />
          <span>Hago la <Link className="underline" href="/legal/declaracion" target="_blank">declaración legal del terapeuta</Link>.</span>
        </label>
      </fieldset>

      <fieldset className="grid gap-3">
        <legend className="font-medium text-zinc-900 dark:text-zinc-100">Opcional</legend>
        <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
          <input type="checkbox" name="offers" className="mt-1 h-5 w-5" />
          <span>Acepto recibir por mail ofertas de otros servicios propios del sitio (<Link className="underline" href="/legal/ofertas" target="_blank">ver detalle</Link>). Podés retirarlo cuando quieras.</span>
        </label>
      </fieldset>

      <button type="submit" disabled={pending}
        className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900">
        {pending ? "Creando tu cuenta…" : "Crear mi perfil"}
      </button>
      <p role="alert" aria-live="polite" className="text-red-700 dark:text-red-400">{state.status === "error" ? state.message : ""}</p>
    </form>
  );
}
