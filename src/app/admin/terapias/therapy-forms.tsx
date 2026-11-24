"use client";

import { useActionState, useState } from "react";
import { THERAPY_CODE_PATTERN, THERAPY_LIMITS, proposeTherapyCode } from "@/lib/admin/therapy-admin";
import { addTherapy, setTherapyActive, type ActionState } from "./actions";

const INITIAL: ActionState = { status: "idle", message: "" };
const FIELD = "min-h-11 w-full rounded-xl border border-campo bg-superficie p-3 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento";
const LABEL = "font-medium text-tinta";
const HELP = "text-sm text-apagado";
const PRIMARY = "inline-flex min-h-11 items-center justify-center rounded-full bg-boton px-5 font-medium text-boton-texto focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50";
const SECONDARY = "inline-flex min-h-11 items-center justify-center rounded-full border border-tinta px-4 text-sm font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50";

export function AddTherapyForm({ defaultName }: { defaultName: string }) {
  const [state, action, pending] = useActionState(addTherapy, INITIAL);
  const [name, setName] = useState(defaultName);
  const [code, setCode] = useState(proposeTherapyCode(defaultName));
  // The code follows the name until the administrator edits it by hand. / El código sigue al nombre hasta que el admin lo edita a mano.
  const [codeEdited, setCodeEdited] = useState(false);
  const ready = name.trim().length > 0 && THERAPY_CODE_PATTERN.test(code.trim());

  return (
    <form action={action} className="grid gap-4 rounded-xl border-2 border-acento bg-superficie p-5">
      <h2 id="nueva" className="font-display text-xl font-semibold text-tinta">Agregar una terapia</h2>
      <div className="grid gap-1">
        <label htmlFor="therapy-name" className={LABEL}>Nombre</label>
        <input id="therapy-name" name="name" type="text" required maxLength={THERAPY_LIMITS.name} autoComplete="off" value={name}
          onChange={(event) => {
            setName(event.target.value);
            if (!codeEdited) setCode(proposeTherapyCode(event.target.value));
          }}
          aria-describedby="therapy-name-help" className={FIELD} />
        <p id="therapy-name-help" className={HELP}>Solo el nombre, sin descripción. Es lo que ven los pacientes y los terapeutas.</p>
      </div>
      <div className="grid gap-1">
        <label htmlFor="therapy-short" className={LABEL}>Nombre corto (opcional)</label>
        <input id="therapy-short" name="shortName" type="text" maxLength={THERAPY_LIMITS.shortName} autoComplete="off" aria-describedby="therapy-short-help" className={FIELD} />
        <p id="therapy-short-help" className={HELP}>Para la tarjeta, hasta {THERAPY_LIMITS.shortName} caracteres. Si el nombre ya es corto, dejalo vacío.</p>
      </div>
      <div className="grid gap-1">
        <label htmlFor="therapy-code" className={LABEL}>Código interno</label>
        <input id="therapy-code" name="code" type="text" required maxLength={THERAPY_LIMITS.code} autoComplete="off" spellCheck={false} value={code}
          onChange={(event) => { setCode(event.target.value); setCodeEdited(true); }}
          aria-describedby="therapy-code-help" className={FIELD} />
        <p id="therapy-code-help" className={HELP}>Se propone solo a partir del nombre. No se puede cambiar después: minúsculas sin tildes, números y «_».</p>
      </div>
      <label className="flex items-start gap-3 text-tinta">
        <input type="checkbox" name="active" defaultChecked className="mt-1 h-5 w-5 accent-acento" />
        <span>Visible para todos desde ahora. Destildala para crearla oculta (por ejemplo, una profesión de salud regulada).</span>
      </label>
      {state.status === "error" && <p role="alert" className="text-peligro-texto">{state.message}</p>}
      <button type="submit" disabled={pending || !ready} className={PRIMARY}>{pending ? "Agregando…" : "Agregar terapia"}</button>
    </form>
  );
}

export function TherapyToggle({ therapyId, name, isActive, profiles }: { therapyId: number; name: string; isActive: boolean; profiles: number }) {
  const [state, action, pending] = useActionState(setTherapyActive, INITIAL);
  const hide = isActive;
  return (
    <form
      action={action}
      onSubmit={(event) => {
        // Hiding is the delicate move: say what changes before doing it. / Ocultar es lo delicado: se dice qué cambia antes de hacerlo.
        if (hide && !window.confirm(
          `«${name}» la tienen ${profiles} ${profiles === 1 ? "perfil" : "perfiles"}. Si la ocultás, los visitantes dejan de verla y no se podrán aprobar revisiones que la elijan hasta que la muestres de nuevo. ¿Ocultar?`,
        )) event.preventDefault();
      }}
      className="grid gap-1"
    >
      <input type="hidden" name="therapyId" value={therapyId} />
      <input type="hidden" name="active" value={hide ? "false" : "true"} />
      <button type="submit" disabled={pending} className={SECONDARY}>
        {pending ? "Guardando…" : hide ? "Ocultar" : "Mostrar"}
      </button>
      {state.status === "error" && <p role="alert" className="text-sm text-peligro-texto">{state.message}</p>}
    </form>
  );
}
