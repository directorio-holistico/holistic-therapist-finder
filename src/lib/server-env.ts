// Secret environment variables, for the server only (never imported from a component that runs in the browser).
// Like env.ts nothing runs at import time, and an error names the variable and the rule, never the value.
// Variables de entorno secretas, solo para el servidor (nunca se importa desde un componente que corre en el navegador).
// Como en env.ts, nada corre al importar, y un error nombra la variable y la regla, nunca el valor.

import { z } from "zod";
import { looksLikeSecretKey } from "@/lib/env";

export type ServerEnv = {
  serviceRoleKey: string;
  rateLimitHmacKey: string;
  turnstileSecretKey: string;
};

type EnvSource = Record<string, string | undefined>;

// Cloudflare's dummy secret keys accept ANY token: they are for local tests only and must never run on the real site.
// Las claves secretas de prueba de Cloudflare aceptan CUALQUIER token: son solo para pruebas locales y nunca deben correr en el sitio real.
const DUMMY_TURNSTILE_SECRET = /^[123]x0{30,}[A-Z]{2}$/;

export function isDummyTurnstileSecret(value: string): boolean {
  return DUMMY_TURNSTILE_SECRET.test(value);
}

const serverEnvSchema = z.object({
  SUPABASE_SERVICE_ROLE_KEY: z
    .string()
    .trim()
    .min(20, "must be the secret (service role) key of the project / debe ser la clave secreta (service role) del proyecto")
    .refine(looksLikeSecretKey, "that is not a SECRET key: the public one must never go here / esa no es una clave SECRETA: la pública nunca va acá"),
  RATE_LIMIT_HMAC_KEY: z
    .string()
    .trim()
    .min(32, "must have at least 32 characters (random) / debe tener al menos 32 caracteres (al azar)"),
  TURNSTILE_SECRET_KEY: z
    .string()
    .trim()
    .min(10, "must be the Turnstile secret key / debe ser la clave secreta de Turnstile"),
});

// isRealSite = the production site (Vercel production). There a dummy Turnstile key is refused.
// isRealSite = el sitio real (producción de Vercel). Ahí una clave de prueba de Turnstile se rechaza.
export function parseServerEnv(source: EnvSource, isRealSite: boolean): ServerEnv {
  const result = serverEnvSchema.safeParse(source);
  if (!result.success) {
    const problems = result.error.issues.map((issue) => `${issue.path.join(".") || "(env)"}: ${issue.message}`).join("; ");
    throw new Error(`Invalid server environment / Entorno de servidor inválido: ${problems}`);
  }
  if (isRealSite && isDummyTurnstileSecret(result.data.TURNSTILE_SECRET_KEY)) {
    throw new Error(
      "Invalid server environment / Entorno de servidor inválido: TURNSTILE_SECRET_KEY: a dummy test key cannot be used on the real site / una clave de prueba no se puede usar en el sitio real",
    );
  }
  return {
    serviceRoleKey: result.data.SUPABASE_SERVICE_ROLE_KEY,
    rateLimitHmacKey: result.data.RATE_LIMIT_HMAC_KEY,
    turnstileSecretKey: result.data.TURNSTILE_SECRET_KEY,
  };
}

export function getServerEnv(): ServerEnv {
  return parseServerEnv(
    {
      SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
      RATE_LIMIT_HMAC_KEY: process.env.RATE_LIMIT_HMAC_KEY,
      TURNSTILE_SECRET_KEY: process.env.TURNSTILE_SECRET_KEY,
    },
    process.env.VERCEL_ENV === "production",
  );
}
