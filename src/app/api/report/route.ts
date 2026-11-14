// POST /api/report  { profileId, reason, details, email, token }  ->  { ok: true }
// The ONLY way a report is created (ADR-0003): bot check, then ONE database call that counts the origin and creates the report.
// Nothing sensitive is logged: no address, no Turnstile token, no text of the report, no mail. The answer is never cached.
// POST /api/report  { profileId, reason, details, email, token }  ->  { ok: true }
// La ÚNICA forma de crear una denuncia (ADR-0003): verificación anti-bots y UNA llamada a la base que cuenta el origen y crea la
// denuncia. No se escribe nada sensible en logs: ni dirección, ni token, ni el texto de la denuncia, ni el mail. Nunca se cachea.

import { NextResponse } from "next/server";
import { REPORT_RESPONSES, reportProfile, type DatabaseReport } from "@/lib/report";
import { getServerEnv, type ServerEnv } from "@/lib/server-env";
import { createServiceClient } from "@/lib/supabase/service-client";
import { verifyTurnstile } from "@/lib/turnstile";

const NO_STORE = { "Cache-Control": "no-store" };
const MAX_BODY_CHARACTERS = 8192;

function answer(status: keyof typeof REPORT_RESPONSES) {
  const { http, message } = REPORT_RESPONSES[status];
  return NextResponse.json({ error: message }, { status: http, headers: NO_STORE });
}

export async function POST(request: Request) {
  if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) return answer("bad_request");

  let body: unknown;
  try {
    const text = await request.text();
    if (text.length > MAX_BODY_CHARACTERS) return answer("bad_request");
    body = JSON.parse(text);
  } catch {
    return answer("bad_request");
  }

  // Secrets are read only when a step needs them: a bad request is answered as such even without configuration.
  // Los secretos se leen solo cuando un paso los necesita: un pedido malo se responde como tal aunque falte configuración.
  let env: ServerEnv | null = null;
  const ready = (): ServerEnv => (env ??= getServerEnv());

  let outcome;
  try {
    outcome = await reportProfile(
      { body, headers: request.headers },
      {
        hmacKey: () => ready().rateLimitHmacKey,
        allowMissingAddress: process.env.NODE_ENV !== "production",
        verify: (token, remoteIp) => verifyTurnstile(token, ready().turnstileSecretKey, remoteIp),
        callDatabase: async (report, hash): Promise<DatabaseReport> => {
          const { error } = await createServiceClient(ready()).rpc("report_profile_limited", {
            p_profile_id: report.profileId,
            p_reason_code: report.reason,
            p_details: report.details,
            p_reporter_email: report.email,
            p_origin_hash: hash,
          });
          if (error) {
            if (error.code !== "RL429" && error.code !== "22023") console.error("report: database error:", error.code ?? "no code");
            return { ok: false, code: error.code ?? null };
          }
          return { ok: true };
        },
      },
    );
  } catch (error) {
    console.error("report: server error:", error instanceof Error ? error.message : "unknown");
    return answer("error");
  }

  if (outcome.status === "ok") return NextResponse.json({ ok: true }, { headers: NO_STORE });
  return answer(outcome.status);
}
