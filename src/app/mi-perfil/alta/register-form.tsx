"use client";

import Link from "next/link";
import { useActionState } from "react";
import { registerTherapist, type RegisterState } from "./actions";

const INITIAL: RegisterState = { status: "idle", message: "" };
const FIELD = "min-h-11 rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";

export function RegisterForm({ suggestedName }: { suggestedName: string }) {
  const [state, action, pending] = useActionState(registerTherapist, INITIAL);
  return (
    <form action={action} className="mt-6 grid gap-4" noValidate>
      <div className="grid gap-1">
        <label htmlFor="fullName" className="font-medium text-tinta">Tu nombre completo</label>
        <input id="fullName" name="fullName" type="text" autoComplete="name" required maxLength={120}
          defaultValue={suggestedName} aria-describedby="fullName-help" className={FIELD} />
        <p id="fullName-help" className="text-sm text-apagado">
          Es el nombre de tu cuenta. El nombre que se muestra en el perfil lo elegís después.
        </p>
      </div>

      <fieldset className="grid gap-3">
        <legend className="font-medium text-tinta">Para continuar necesitamos que aceptes</legend>
        <label className="flex items-start gap-3 text-tinta">
          <input type="checkbox" name="terms" required className="mt-1 h-5 w-5 accent-acento" />
          <span>Leí y acepto los <Link className="text-acento underline underline-offset-4" href="/legal/terminos" target="_blank">términos y condiciones</Link>.</span>
        </label>
        <label className="flex items-start gap-3 text-tinta">
          <input type="checkbox" name="privacy" required className="mt-1 h-5 w-5 accent-acento" />
          <span>Leí la <Link className="text-acento underline underline-offset-4" href="/legal/privacidad" target="_blank">política de privacidad</Link> y estoy de acuerdo.</span>
        </label>
        <label className="flex items-start gap-3 text-tinta">
          <input type="checkbox" name="legalDeclaration" required className="mt-1 h-5 w-5 accent-acento" />
          <span>Hago la <Link className="text-acento underline underline-offset-4" href="/legal/declaracion" target="_blank">declaración legal del terapeuta</Link>.</span>
        </label>
      </fieldset>

      <fieldset className="grid gap-3">
        <legend className="font-medium text-tinta">Opcional</legend>
        <label className="flex items-start gap-3 text-tinta">
          <input type="checkbox" name="offers" className="mt-1 h-5 w-5 accent-acento" />
          <span>Acepto recibir por mail ofertas de otros servicios propios del sitio (<Link className="text-acento underline underline-offset-4" href="/legal/ofertas" target="_blank">ver detalle</Link>). Podés retirarlo cuando quieras.</span>
        </label>
      </fieldset>

      <button type="submit" disabled={pending}
        className="inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-60">
        {pending ? "Creando tu cuenta…" : "Crear mi perfil"}
      </button>
      <p role="alert" aria-live="polite" className="text-peligro-texto">{state.status === "error" ? state.message : ""}</p>
    </form>
  );
}
