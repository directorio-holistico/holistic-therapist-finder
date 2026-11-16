// Light/dark theme chosen by the visitor. Default: light (not the device setting).
// Tema claro/oscuro elegido por el visitante. Por defecto: claro (no el del dispositivo).
export type Theme = "claro" | "oscuro";

export const THEME_STORAGE_KEY = "faro-tema";

/** Only "oscuro" is accepted as dark; anything else is light. / Solo "oscuro" es oscuro; todo lo demás es claro. */
export function parseTheme(value: string | null | undefined): Theme {
  return value === "oscuro" ? "oscuro" : "claro";
}

/**
 * Runs in <head> before painting, so the page does not flash. Reads one value, never throws.
 * Se ejecuta en <head> antes de pintar, para que no haya parpadeo. Lee un valor y nunca falla.
 */
export const THEME_INIT_SCRIPT = `(function(){var t="claro";try{if(window.localStorage.getItem(${JSON.stringify(
  THEME_STORAGE_KEY,
)})==="oscuro"){t="oscuro";}}catch(e){}document.documentElement.setAttribute("data-theme",t);})();`;
