// Spends the one-use token and opens the session (cookie). Only POST exists: a plain GET (scanner, preview) does nothing.
// Gasta el token de un solo uso y abre la sesión (cookie). Solo existe POST: un GET común (escáner, vista previa) no hace nada.

import { NextResponse, type NextRequest } from "next/server";
import { confirmSchema, safeNextPath } from "@/lib/auth/params";
import { createServerSupabase } from "@/lib/supabase/server-client";

export async function POST(request: NextRequest) {
  const form = await request.formData();
  const parsed = confirmSchema.safeParse({
    token_hash: form.get("token_hash") ?? undefined,
    type: form.get("type") ?? undefined,
    next: form.get("next") ?? undefined,
  });
  const failed = () => NextResponse.redirect(new URL("/ingresar?error=enlace", request.url), 303);
  if (!parsed.success) return failed();

  const supabase = await createServerSupabase();
  const { error } = await supabase.auth.verifyOtp({ type: parsed.data.type, token_hash: parsed.data.token_hash });
  if (error) return failed();
  return NextResponse.redirect(new URL(safeNextPath(parsed.data.next), request.url), 303);
}
