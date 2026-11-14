// The contact reveal, step by step (ADR-0003): (a) the visitor's address, (b) the Turnstile check, (c) ONE database call that
// counts and reveals in a single transaction. The pieces that touch the outside (Turnstile, the database) come in as
// parameters, so every branch is tested without network.
// El revelado de contacto, paso a paso (ADR-0003): (a) la dirección del visitante, (b) la verificación de Turnstile, (c) UNA llamada
// a la base que cuenta y revela en una sola transacción. Lo que toca el exterior (Turnstile, la base) entra como parámetro, así
// cada rama se prueba sin red.

import { z } from "zod";
import { clientAddress, originHash } from "@/lib/origin";
import { MAX_TOKEN_LENGTH, type TurnstileResult } from "@/lib/turnstile";

export type RevealedContact = { type: string; value: string; whatsapp: boolean };

export type RevealOutcome =
  | { status: "ok"; contacts: RevealedContact[] }
  | { status: "bad_request" }
  | { status: "no_origin" }
  | { status: "captcha_failed" }
  | { status: "captcha_unavailable" }
  | { status: "rate_limited" }
  | { status: "error" };

export type DatabaseReveal =
  | { ok: true; rows: { contact_type: string; value: string; accepts_whatsapp: boolean }[] }
  | { ok: false; code: string | null };

export type RevealDeps = {
  // A function: the secret is read only when it is needed, after the request has been checked.
  hmacKey: () => string;
  // In development there is no proxy that adds the address; this lets a local run work. Never true on the real site.
  allowMissingAddress: boolean;
  verify: (token: string, remoteIp: string | null) => Promise<TurnstileResult>;
  callDatabase: (profileId: string, originHash: string) => Promise<DatabaseReveal>;
};

const requestSchema = z.object({
  profileId: z.guid(),
  token: z.string().min(1).max(MAX_TOKEN_LENGTH),
});

// SQLSTATE of the limit error raised by reveal_contact_limited. / SQLSTATE del error de límite de reveal_contact_limited.
export const RATE_LIMIT_CODE = "RL429";

export async function revealContact(input: { body: unknown; headers: Headers }, deps: RevealDeps): Promise<RevealOutcome> {
  const parsed = requestSchema.safeParse(input.body);
  if (!parsed.success) return { status: "bad_request" };

  const address = clientAddress(input.headers) ?? (deps.allowMissingAddress ? "local-development" : null);
  if (address === null) return { status: "no_origin" };

  const captcha = await deps.verify(parsed.data.token, address === "local-development" ? null : address);
  if (!captcha.ok) return { status: captcha.reason === "unavailable" ? "captcha_unavailable" : "captcha_failed" };

  const result = await deps.callDatabase(parsed.data.profileId, originHash(address, deps.hmacKey()));
  if (!result.ok) return { status: result.code === RATE_LIMIT_CODE ? "rate_limited" : "error" };
  return {
    status: "ok",
    contacts: result.rows.map((row) => ({ type: row.contact_type, value: row.value, whatsapp: row.accepts_whatsapp })),
  };
}

// What the visitor reads for each outcome (no internal detail). / Lo que lee el visitante en cada caso (sin detalle interno).
export const REVEAL_RESPONSES: Record<Exclude<RevealOutcome["status"], "ok">, { http: number; message: string }> = {
  bad_request: { http: 400, message: "No se pudo procesar el pedido." },
  no_origin: { http: 400, message: "No se pudo procesar el pedido." },
  captcha_failed: { http: 403, message: "No pudimos verificar que sos una persona. Probá de nuevo." },
  captcha_unavailable: { http: 503, message: "La verificación no está disponible ahora. Probá de nuevo en unos minutos." },
  rate_limited: { http: 429, message: "Llegaste al límite de contactos que se pueden ver por hoy. Probá de nuevo mañana." },
  error: { http: 500, message: "No pudimos mostrar el contacto. Probá de nuevo en unos minutos." },
};
