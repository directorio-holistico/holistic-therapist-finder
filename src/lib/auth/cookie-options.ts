// Options of the session cookie. Only the SERVER reads it (there is no Supabase client in the browser), so the browser's
// scripts get no access to it (httpOnly): a script injected in a page cannot steal the session. Secure in production (https only).
// Opciones de la cookie de sesión. La lee SOLO el SERVIDOR (no hay cliente de Supabase en el navegador), así los scripts del
// navegador no la ven (httpOnly): un script inyectado en una página no puede robar la sesión. Secure en producción (solo https).

export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
};
