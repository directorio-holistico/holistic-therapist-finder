import type { LegalDocument } from "./types";

export const OFFERS: LegalDocument = {
  code: "offers_consent",
  slug: "ofertas",
  title: "Consentimiento para recibir ofertas (opcional)",
  summary: "Casilla opcional del alta, desmarcada por defecto.",
  sections: [
    {
      id: "consentimiento",
      title: "Qué aceptás",
      blocks: [
        { type: "p", text: "Acepto que el responsable de Faro Holístico me envíe por mail ofertas de otros servicios propios, por ejemplo un sistema de turnos." },
        { type: "ul", items: [
          "Es opcional: si no lo aceptás, tu perfil funciona igual.",
          "Viene desmarcado por defecto.",
          "Podés retirarlo cuando quieras desde tu panel, sin consecuencias para tu perfil.",
          "No se comparten tus datos con terceros para esto.",
        ] },
      ],
    },
  ],
};
