// Server side of the daily limit: reads the request's headers and talks to the database with the SECRET key (service role), the
// only key allowed to run rate_limit_hit and log_search_limited. Nothing sensitive is logged: no address, no hash, no e-mail.
// Lado servidor del límite diario: lee los encabezados del pedido y habla con la base con la clave SECRETA (service role), la única
// que puede ejecutar rate_limit_hit y log_search_limited. No se escribe nada sensible en logs: ni dirección, ni hash, ni mail.

import "server-only";
import { headers } from "next/headers";
import { checkOriginLimit, resolveOrigin, type LimitDeps, type LimitOutcome, type LimitedAction } from "@/lib/rate-limit";
import { getServerEnv } from "@/lib/server-env";
import type { UnmetSearchInput } from "@/lib/search";
import { createServiceClient } from "@/lib/supabase/service-client";

const originDeps = () => ({
  hmacKey: () => getServerEnv().rateLimitHmacKey,
  allowMissingAddress: process.env.NODE_ENV !== "production",
});

const callDatabase: LimitDeps["call"] = async (action: LimitedAction, hash: string) => {
  const { data, error } = await createServiceClient(getServerEnv()).rpc("rate_limit_hit", { p_action: action, p_origin_hash: hash });
  if (error) {
    console.error("rate limit: database error:", error.code ?? "no code");
    return { ok: false };
  }
  return { ok: true, allowed: data === true };
};

// Counts one sign-in action of this visitor. / Cuenta una acción de ingreso de este visitante.
export async function limitOrigin(action: Extract<LimitedAction, "login" | "login_link">): Promise<LimitOutcome> {
  try {
    return await checkOriginLimit(action, await headers(), { ...originDeps(), call: callDatabase });
  } catch (error) {
    // Most likely the server environment: the message names the variable and the rule, never the value.
    console.error("rate limit: server error:", error instanceof Error ? error.message : "unknown");
    return "error";
  }
}

// Best effort: counts and records an unmet search in ONE database call (the database also checks that it truly has no result and
// that the origin is under its limit). A failure here never breaks the page.
// Mejor esfuerzo: cuenta y registra una búsqueda sin resultado en UNA llamada a la base (la base también comprueba que de verdad no
// tenga resultado y que el origen esté bajo su límite). Un fallo acá nunca rompe la página.
export async function recordUnmetSearch(input: UnmetSearchInput): Promise<void> {
  try {
    const origin = resolveOrigin("unmet_search", await headers(), originDeps());
    if (!origin.ok) return;
    const { error } = await createServiceClient(getServerEnv()).rpc("log_search_limited", {
      p_therapy_id: input.therapyId,
      p_location_id: input.locationId,
      // The function has no default for this argument, so it must be sent (null = any mode). The generated type says `string`
      // only because Postgres arguments without a default are typed as required; the function accepts null.
      // La función no tiene valor por defecto para este argumento, así que hay que enviarlo (null = cualquier modalidad). El tipo
      // generado dice `string` solo porque los argumentos sin valor por defecto se tipan como obligatorios; la función acepta null.
      p_service_mode: (input.serviceMode ?? null) as string,
      p_origin_hash: origin.hash,
    });
    if (error) console.error("unmet search: database error:", error.code ?? "no code");
  } catch (error) {
    console.error("unmet search: server error:", error instanceof Error ? error.message : "unknown");
  }
}
