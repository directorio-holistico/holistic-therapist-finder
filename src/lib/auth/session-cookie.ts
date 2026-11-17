// Is there a Supabase session cookie among these cookie names? Only the NAMES are looked at, never the values. The session cookie is
// "sb-<project>-auth-token", split in pieces (".0", ".1") when it is long. The temporary "...-code-verifier" cookie (kept while an
// email link is on its way) is NOT a session.
// ¿Hay una cookie de sesión de Supabase entre estos nombres? Solo se miran los NOMBRES, nunca los valores. La cookie de sesión es
// "sb-<proyecto>-auth-token", partida en trozos (".0", ".1") si es larga. La cookie temporal "...-code-verifier" (se guarda mientras
// viaja un enlace por mail) NO es una sesión.
export function hasSessionCookie(names: readonly string[]): boolean {
  return names.some((name) => /^sb-[A-Za-z0-9-]+-auth-token(\.\d+)?$/.test(name));
}
