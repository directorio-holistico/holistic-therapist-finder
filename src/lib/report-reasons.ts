// The reasons shown in the report form, in Spanish. The catalog lives in the database (report_reasons) but a visitor cannot read
// it, so the form carries this list; a test checks that every code exists in the migration. The database is the one that
// accepts or refuses a code (a deactivated reason is refused there), so this list never decides anything by itself.
// Los motivos que muestra el formulario de denuncia, en español. El catálogo vive en la base (report_reasons) pero un visitante
// no puede leerlo, así que el formulario lleva esta lista; una prueba verifica que cada código exista en la migración. Quien
// acepta o rechaza un código es la base (un motivo desactivado se rechaza ahí), así esta lista nunca decide por sí sola.

export const REPORT_REASONS = [
  { code: "cure_claim", label: "Promete curas o tratamientos de enfermedades" },
  { code: "false_information", label: "Información falsa o engañosa" },
  { code: "inappropriate_content", label: "Contenido inapropiado" },
  { code: "impersonation", label: "Se hace pasar por otra persona" },
  { code: "unsafe_practice", label: "Práctica que puede poner en riesgo a alguien" },
  { code: "other", label: "Otro motivo" },
] as const;

export const REPORT_REASON_CODES: readonly string[] = REPORT_REASONS.map((reason) => reason.code);

export const REPORT_DETAILS_MAX = 1000;
export const REPORT_EMAIL_MAX = 254;

// Shown after a report is sent. It lives here, not in report.ts, because the form (browser) reads it and report.ts uses Node.
// Se muestra al enviar una denuncia. Vive acá y no en report.ts porque la lee el formulario (navegador) y report.ts usa Node.
export const REPORT_SUCCESS_MESSAGE =
  "Recibimos tu denuncia. Una persona la va a revisar; el perfil no se baja de forma automática.";
