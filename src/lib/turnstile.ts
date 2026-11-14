// Verification of the Cloudflare Turnstile token on the server. It fails CLOSED: if Cloudflare cannot be reached, nothing is
// revealed (ADR-0003, point 7). The token is single use and is never logged.
// Verificación del token de Cloudflare Turnstile en el servidor. Falla CERRADO: si no se llega a Cloudflare, no se revela nada
// (ADR-0003, punto 7). El token es de un solo uso y nunca se escribe en logs.

export const TURNSTILE_VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
export const MAX_TOKEN_LENGTH = 2048;
const TIMEOUT_MS = 5000;

export type TurnstileResult = { ok: true } | { ok: false; reason: "invalid" | "unavailable" };

type FetchLike = (url: string, init: { method: string; body: URLSearchParams; signal: AbortSignal }) => Promise<{ ok: boolean; json: () => Promise<unknown> }>;

export async function verifyTurnstile(
  token: string,
  secret: string,
  remoteIp: string | null,
  fetchImpl: FetchLike = fetch as unknown as FetchLike,
): Promise<TurnstileResult> {
  if (token.length === 0 || token.length > MAX_TOKEN_LENGTH) return { ok: false, reason: "invalid" };
  const body = new URLSearchParams({ secret, response: token });
  if (remoteIp) body.set("remoteip", remoteIp);
  try {
    const response = await fetchImpl(TURNSTILE_VERIFY_URL, { method: "POST", body, signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!response.ok) return { ok: false, reason: "unavailable" };
    const data = (await response.json()) as { success?: unknown };
    return data.success === true ? { ok: true } : { ok: false, reason: "invalid" };
  } catch {
    return { ok: false, reason: "unavailable" };
  }
}
