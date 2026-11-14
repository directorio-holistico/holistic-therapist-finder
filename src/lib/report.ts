// Reporting a profile, step by step (ADR-0003): (a) the request is checked, (b) the visitor's address, (c) the Turnstile check,
// (d) ONE database call that counts the origin and creates the report in a single transaction. Like the reveal, what touches the
// outside comes in as parameters, so every branch is tested without network.
// Denunciar un perfil, paso a paso (ADR-0003): (a) se valida el pedido, (b) la dirección del visitante, (c) la verificación de
// Turnstile, (d) UNA llamada a la base que cuenta el origen y crea la denuncia en una sola transacción. Como el revelado, lo que
// toca el exterior entra como parámetro, así cada rama se prueba sin red.

import { z } from "zod";
import { clientAddress, originHash } from "@/lib/origin";
import { REPORT_DETAILS_MAX, REPORT_EMAIL_MAX, REPORT_REASON_CODES } from "@/lib/report-reasons";
import { RATE_LIMIT_CODE } from "@/lib/reveal";
import { MAX_TOKEN_LENGTH, type TurnstileResult } from "@/lib/turnstile";

export type ReportOutcome =
  | { status: "ok" }
  | { status: "bad_request" }
  | { status: "no_origin" }
  | { status: "captcha_failed" }
  | { status: "captcha_unavailable" }
  | { status: "rate_limited" }
  | { status: "invalid" }
  | { status: "error" };

export type ReportData = { profileId: string; reason: string; details: string; email: string };
export type DatabaseReport = { ok: true } | { ok: false; code: string | null };

export type ReportDeps = {
  hmacKey: () => string;
  allowMissingAddress: boolean;
  verify: (token: string, remoteIp: string | null) => Promise<TurnstileResult>;
  callDatabase: (report: ReportData, originHash: string) => Promise<DatabaseReport>;
};

const EMAIL_SHAPE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Optional fields come as "" when empty (the database turns "" into null). The email is lower case, as the database stores it.
// Los campos opcionales llegan como "" si están vacíos (la base convierte "" en null). El mail va en minúsculas, como lo guarda la base.
export const reportRequestSchema = z.object({
  profileId: z.guid(),
  reason: z.string().refine((code) => REPORT_REASON_CODES.includes(code)),
  details: z.string().trim().max(REPORT_DETAILS_MAX).default(""),
  email: z.string().trim().toLowerCase().max(REPORT_EMAIL_MAX).refine((value) => value === "" || EMAIL_SHAPE.test(value)).default(""),
  token: z.string().min(1).max(MAX_TOKEN_LENGTH),
});

export async function reportProfile(input: { body: unknown; headers: Headers }, deps: ReportDeps): Promise<ReportOutcome> {
  const parsed = reportRequestSchema.safeParse(input.body);
  if (!parsed.success) return { status: "bad_request" };
  const { token, ...report } = parsed.data;

  const address = clientAddress(input.headers) ?? (deps.allowMissingAddress ? "local-development" : null);
  if (address === null) return { status: "no_origin" };

  const captcha = await deps.verify(token, address === "local-development" ? null : address);
  if (!captcha.ok) return { status: captcha.reason === "unavailable" ? "captcha_unavailable" : "captcha_failed" };

  const result = await deps.callDatabase(report, originHash(address, deps.hmacKey(), "report"));
  if (result.ok) return { status: "ok" };
  if (result.code === RATE_LIMIT_CODE) return { status: "rate_limited" };
  // 22023: unknown or hidden profile, a reason the database refuses, a bad email. The visitor is never told which one.
  // 22023: perfil inexistente u oculto, un motivo que la base rechaza, un mail inválido. Al visitante nunca se le dice cuál.
  return { status: result.code === "22023" ? "invalid" : "error" };
}

// What the visitor reads for each outcome (no internal detail). / Lo que lee el visitante en cada caso (sin detalle interno).
export const REPORT_RESPONSES: Record<Exclude<ReportOutcome["status"], "ok">, { http: number; message: string }> = {
  bad_request: { http: 400, message: "Revisá los datos: elegí un motivo y, si dejás mail, que sea válido." },
  no_origin: { http: 400, message: "No se pudo procesar el pedido." },
  captcha_failed: { http: 403, message: "No pudimos verificar que sos una persona. Probá de nuevo." },
  captcha_unavailable: { http: 503, message: "La verificación no está disponible ahora. Probá de nuevo en unos minutos." },
  rate_limited: { http: 429, message: "Llegaste al límite de denuncias que se pueden enviar por hoy. Probá de nuevo mañana." },
  invalid: { http: 422, message: "No pudimos registrar la denuncia: el perfil ya no está disponible o los datos no son válidos." },
  error: { http: 500, message: "No pudimos enviar la denuncia. Probá de nuevo en unos minutos." },
};
