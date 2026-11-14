// Cloudflare Turnstile in the browser: the script is loaded only when a person asks for something that needs the check
// ("Ver contacto", "Denunciar"). One shared loader, so two components never add the script twice.
// Cloudflare Turnstile en el navegador: el script se carga solo cuando una persona pide algo que necesita la comprobación
// ("Ver contacto", "Denunciar"). Un cargador compartido, así dos componentes nunca agregan el script dos veces.

export type TurnstileApi = {
  render: (element: HTMLElement, options: Record<string, unknown>) => string;
  remove: (widgetId: string) => void;
};

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

const SCRIPT_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

let scriptPromise: Promise<void> | null = null;

export function loadTurnstile(): Promise<void> {
  if (window.turnstile) return Promise.resolve();
  scriptPromise ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = SCRIPT_URL;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => {
      scriptPromise = null;
      reject(new Error("turnstile script"));
    };
    document.head.appendChild(script);
  });
  return scriptPromise;
}
