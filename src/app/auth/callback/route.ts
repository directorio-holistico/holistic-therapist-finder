// Landing of the DEFAULT email link (Supabase's own template): Supabase verifies the mail and sends the person here with a
// one-use "code". The code only works in the SAME browser that asked for the link (it needs the verifier cookie that browser
// holds), so a mail scanner that opens the link cannot use it. Opened on another device it fails and asks for a new link.
// Aterrizaje del enlace de mail POR DEFECTO (plantilla propia de Supabase): Supabase verifica el mail y manda a la persona acá
// con un "code" de un solo uso. Solo sirve en el MISMO navegador que pidió el enlace (necesita la cookie verificadora de ese
// navegador), así que un escáner de mail que abra el enlace no lo puede usar. En otro dispositivo falla y pide un enlace nuevo.

import { NextResponse, type NextRequest } from "next/server";
import { safeNextPath } from "@/lib/auth/params";
import { createServerSupabase } from "@/lib/supabase/server-client";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const failed = () => NextResponse.redirect(new URL("/ingresar?error=enlace", request.url));
  if (!code || code.length > 300 || /\s/.test(code)) return failed();

  const supabase = await createServerSupabase();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) return failed();
  return NextResponse.redirect(new URL(safeNextPath(searchParams.get("next")), request.url));
}
