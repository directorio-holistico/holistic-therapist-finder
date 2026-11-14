// POST /api/reveal  { profileId, token }  ->  { contacts: [{ type, value, whatsapp }] }
// The ONLY way a phone or a mail leaves the database for a visitor (ADR-0003). Nothing sensitive is logged: no address, no
// Turnstile token, no contact. The answer is never cached.
// POST /api/reveal  { profileId, token }  ->  { contacts: [{ type, value, whatsapp }] }
// La ÚNICA forma en que un teléfono o un mail sale de la base hacia un visitante (ADR-0003). No se escribe nada sensible en logs:
// ni dirección, ni token de Turnstile, ni contactos. La respuesta nunca se guarda en caché.

import { NextResponse } from "next/server";
import { REVEAL_RESPONSES, revealContact, type DatabaseReveal } from "@/lib/reveal";
import { getServerEnv, type ServerEnv } from "@/lib/server-env";
import { createServiceClient } from "@/lib/supabase/service-client";
import { verifyTurnstile } from "@/lib/turnstile";

const NO_STORE = { "Cache-Control": "no-store" };
const MAX_BODY_BYTES = 4096;

function answer(status: keyof typeof REVEAL_RESPONSES) {
  const { http, message } = REVEAL_RESPONSES[status];
  return NextResponse.json({ error: message }, { status: http, headers: NO_STORE });
}

export async function POST(request: Request) {
  if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) return answer("bad_request");

  let body: unknown;
  try {
    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) return answer("bad_request");
    body = JSON.parse(text);
  } catch {
    return answer("bad_request");
  }

  // The secrets are read only when a step needs them, so a bad request is answered as a bad request even without configuration.
  // Los secretos se leen solo cuando un paso los necesita, así un pedido malo se responde como pedido malo aunque falte configuración.
  let env: ServerEnv | null = null;
  const ready = (): ServerEnv => (env ??= getServerEnv());

  let outcome;
  try {
    outcome = await revealContact(
      { body, headers: request.headers },
      {
        hmacKey: () => ready().rateLimitHmacKey,
        allowMissingAddress: process.env.NODE_ENV !== "production",
        verify: (token, remoteIp) => verifyTurnstile(token, ready().turnstileSecretKey, remoteIp),
        callDatabase: async (profileId, hash): Promise<DatabaseReveal> => {
          const { data, error } = await createServiceClient(ready()).rpc("reveal_contact_limited", {
            p_profile_id: profileId,
            p_origin_hash: hash,
          });
          if (error) {
            if (error.code !== "RL429") console.error("reveal: database error:", error.code ?? "no code");
            return { ok: false, code: error.code ?? null };
          }
          return { ok: true, rows: data ?? [] };
        },
      },
    );
  } catch (error) {
    // Most likely the server environment: the message names the variable and the rule, never the value.
    console.error("reveal: server error:", error instanceof Error ? error.message : "unknown");
    return answer("error");
  }

  if (outcome.status === "ok") return NextResponse.json({ contacts: outcome.contacts }, { headers: NO_STORE });
  return answer(outcome.status);
}
