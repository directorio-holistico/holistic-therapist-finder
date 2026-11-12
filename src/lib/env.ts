// Validated environment variables. Nothing runs at import time: values are read and checked when first needed,
// so a build or a test that does not touch Supabase does not need them.
// Variables de entorno validadas. Nada corre al importar: los valores se leen y validan cuando hacen falta,
// así un build o una prueba que no usa Supabase no los necesita.
//
// Only PUBLIC values live here. The secret keys (service role, HMAC) get their own server-only module when a feature needs them.
// Acá solo van valores PÚBLICOS. Las claves secretas (service role, HMAC) tendrán su propio módulo solo de servidor cuando una función las necesite.

import { z } from "zod";

export type PublicEnv = {
  supabaseUrl: string;
  supabaseAnonKey: string;
};

type EnvSource = Record<string, string | undefined>;

// https only; plain http is accepted for a local machine (development against a local Supabase).
// Solo https; http plano se acepta en la máquina local (desarrollo contra un Supabase local).
function isAllowedUrl(value: string): boolean {
  try {
    const url = new URL(value);
    if (url.protocol === "https:") return true;
    return url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1");
  } catch {
    return false;
  }
}

// A secret (service role) key must never be used where the public key goes. New-style secret keys start with
// "sb_secret_"; old-style keys are JWTs whose payload carries the role.
// Una clave secreta (service role) nunca debe usarse donde va la pública. Las nuevas empiezan con "sb_secret_";
// las viejas son JWT cuyo payload lleva el rol.
function looksLikeSecretKey(value: string): boolean {
  if (value.startsWith("sb_secret_")) return true;
  const parts = value.split(".");
  if (parts.length !== 3 || !parts[1]) return false;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const payload: unknown = JSON.parse(atob(padded));
    return typeof payload === "object" && payload !== null && (payload as { role?: unknown }).role === "service_role";
  } catch {
    return false;
  }
}

const publicEnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z
    .string()
    .trim()
    .refine(isAllowedUrl, "must be an https address (http only for localhost) / debe ser una dirección https (http solo en localhost)"),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z
    .string()
    .trim()
    .min(20, "must be the public key of the project / debe ser la clave pública del proyecto")
    .refine((value) => !looksLikeSecretKey(value), "that is a SECRET key: use the public one / esa es una clave SECRETA: usá la pública"),
});

// Pure function (easy to test). Errors name the variable and the rule, never the value.
// Función pura (fácil de probar). Los errores nombran la variable y la regla, nunca el valor.
export function parsePublicEnv(source: EnvSource): PublicEnv {
  const result = publicEnvSchema.safeParse(source);
  if (!result.success) {
    const problems = result.error.issues
      .map((issue) => `${issue.path.join(".") || "(env)"}: ${issue.message}`)
      .join("; ");
    throw new Error(`Invalid environment / Entorno inválido: ${problems}`);
  }
  return {
    supabaseUrl: result.data.NEXT_PUBLIC_SUPABASE_URL,
    supabaseAnonKey: result.data.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  };
}

// Next.js only inlines NEXT_PUBLIC_* values when they are written out in full, so each one is referenced by name.
// Next.js solo reemplaza los NEXT_PUBLIC_* cuando están escritos completos, por eso cada uno se nombra explícitamente.
export function getPublicEnv(): PublicEnv {
  return parsePublicEnv({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  });
}
