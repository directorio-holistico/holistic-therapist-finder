// Daily limit per origin for the sign-in actions and the unmet-search log (follows ADR-0003). The website server reads the visitor's
// address, turns it into a keyed hash (src/lib/origin.ts) and asks the database to count BEFORE doing the work. The database only
// ever sees 64 hex characters: never an address, never an e-mail. What touches the outside comes in as parameters, so every branch
// is tested without network.
// Límite diario por origen para las acciones de ingreso y el registro de búsquedas sin resultado (sigue el ADR-0003). El servidor
// de la web lee la dirección del visitante, la convierte en un hash con clave (src/lib/origin.ts) y le pide a la base que cuente
// ANTES de hacer el trabajo. La base solo ve 64 caracteres hexadecimales: nunca una dirección ni un mail. Lo que toca el exterior
// entra como parámetro, así cada rama se prueba sin red.

import { clientAddress, originHash, type OriginPurpose } from "@/lib/origin";

export type LimitedAction = Extract<OriginPurpose, "login" | "login_link" | "unmet_search">;

// allowed = go ahead; blocked = the origin reached its daily limit; no_origin = the address is unknown (never on the real site);
// error = the limiter itself failed (the caller must NOT skip the limit: it refuses the action).
// allowed = seguir; blocked = el origen llegó a su límite diario; no_origin = no se conoce la dirección (nunca en el sitio real);
// error = falló el propio límite (quien llama NO debe saltearlo: rechaza la acción).
export type LimitOutcome = "allowed" | "blocked" | "no_origin" | "error";

export type OriginDeps = {
  // A function: the secret is read only when needed. / Una función: el secreto se lee solo cuando hace falta.
  hmacKey: () => string;
  // In development there is no proxy that adds the address. Never true on the real site. / En desarrollo no hay proxy que agregue la dirección. Nunca true en el sitio real.
  allowMissingAddress: boolean;
};

export type LimitDeps = OriginDeps & {
  call: (action: LimitedAction, originHash: string) => Promise<{ ok: true; allowed: boolean } | { ok: false }>;
};

export type OriginResult = { ok: true; hash: string } | { ok: false; reason: "no_origin" | "error" };

export function resolveOrigin(action: LimitedAction, headers: Headers, deps: OriginDeps): OriginResult {
  const address = clientAddress(headers) ?? (deps.allowMissingAddress ? "local-development" : null);
  if (address === null) return { ok: false, reason: "no_origin" };
  try {
    return { ok: true, hash: originHash(address, deps.hmacKey(), action) };
  } catch {
    return { ok: false, reason: "error" };
  }
}

export async function checkOriginLimit(action: LimitedAction, headers: Headers, deps: LimitDeps): Promise<LimitOutcome> {
  const origin = resolveOrigin(action, headers, deps);
  if (!origin.ok) return origin.reason;
  try {
    const result = await deps.call(action, origin.hash);
    if (!result.ok) return "error";
    return result.allowed ? "allowed" : "blocked";
  } catch {
    return "error";
  }
}

// What the person sees when a sign-in action is refused. One message per case, the same for every account (nothing here tells
// whether an e-mail is registered). / Lo que ve la persona cuando se rechaza una acción de ingreso. Un mensaje por caso, igual para toda cuenta.
export const LIMIT_MESSAGES = {
  blocked: "Llegaste al máximo de intentos desde esta conexión. Probá de nuevo más tarde.",
  unavailable: "No pudimos procesar el pedido ahora. Probá de nuevo en unos minutos.",
} as const;

export function limitMessage(outcome: Exclude<LimitOutcome, "allowed">): string {
  return outcome === "blocked" ? LIMIT_MESSAGES.blocked : LIMIT_MESSAGES.unavailable;
}
