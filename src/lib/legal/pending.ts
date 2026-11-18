// Reads the documents the logged-in therapist still has to accept, with their own session. The database computes it
// (my_pending_documents); it raises an error for a login without a person, so call it only for someone with a profile.
// Lee los documentos que el terapeuta ingresado todavía tiene que aceptar, con su propia sesión. La base lo calcula
// (my_pending_documents); falla para un ingreso sin persona, así que llamarla solo para quien ya tiene perfil.

import { parsePendingDocuments } from "@/lib/legal/acceptance";
import type { LegalDocumentCode } from "@/lib/legal/types";
import type { createServerSupabase } from "@/lib/supabase/server-client";

type ServerSupabase = Awaited<ReturnType<typeof createServerSupabase>>;

// null = could not be read (the caller must show an error, never assume "nothing pending").
// null = no se pudo leer (quien llama debe mostrar un error, nunca asumir "nada pendiente").
export async function loadPendingDocuments(supabase: ServerSupabase): Promise<LegalDocumentCode[] | null> {
  const result = await supabase.rpc("my_pending_documents");
  if (result.error) {
    console.error(`my_pending_documents failed / falló my_pending_documents: ${result.error.code ?? "unknown"}`);
    return null;
  }
  return parsePendingDocuments(result.data);
}
