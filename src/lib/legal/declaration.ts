import type { LegalDocument } from "./types";

export const DECLARATION: LegalDocument = {
  code: "legal_declaration",
  slug: "declaracion",
  title: "Declaración legal del terapeuta",
  summary: "Lo que declarás al darte de alta como terapeuta.",
  sections: [
    {
      id: "declaro",
      title: "Al darme de alta declaro que:",
      blocks: [
        { type: "ul", items: [
          "Soy mayor de edad y los datos que cargo son verdaderos y actuales.",
          "Tengo derecho a ofrecer las terapias que publico en los lugares donde las ofrezco, y cumplo las normas que me sean aplicables.",
          "No prometo curas ni resultados, no afirmo que mis terapias traten, prevengan o curen enfermedades, y no las presento como reemplazo de la atención médica o psicológica.",
          "No pido ni sugiero a nadie que abandone o evite un tratamiento médico.",
          "No incluyo en mi perfil datos de pacientes ni datos de salud de otras personas.",
          "Tengo derecho a usar la foto y los textos que publico.",
          "Autorizo que mi teléfono y mi mail se muestren a quien pida ver mi contacto desde el sitio.",
          "Las tarifas que cargo son reales; las confirmo y las mantengo al día.",
          "Acepto que mi perfil y cada cambio pasen por revisión antes de publicarse, y que el sitio pueda rechazarlos, pausarlos o suspenderlos con un motivo.",
          "Si marco LNT® – La Nueva Terapia – Método Schwiderski, confirmo que estoy formado y autorizado para ofrecerla, y acepto que el responsable del sitio valide esa declaración durante la revisión.",
          "Leí y acepto los términos y la política de privacidad.",
        ] },
      ],
    },
  ],
};
