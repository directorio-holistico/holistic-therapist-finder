import { MAX_THERAPIES_PER_PROFILE, RATES_VALIDITY_MONTHS, REVIEW_BUSINESS_DAYS } from "./facts";
import type { LegalDocument } from "./types";

export const TERMS: LegalDocument = {
  code: "terms",
  slug: "terminos",
  title: "Términos y condiciones de uso",
  summary: "Cómo funciona Faro Holístico, qué es y qué no es, y las reglas para terapeutas y visitantes.",
  sections: [
    {
      id: "que-es",
      title: "1. Qué es Faro Holístico",
      blocks: [
        { type: "p", text: "Faro Holístico es un directorio gratuito de terapeutas holísticos. Una persona elige una terapia y una zona, ve los terapeutas que la ofrecen y puede ver sus datos de contacto para comunicarse con ellos." },
        { type: "p", text: "El sitio solo crea esa conexión. No da turnos, no cobra, no guarda historias clínicas, no ofrece chat y no publica reseñas ni puntajes de pacientes." },
      ],
    },
    {
      id: "quienes",
      title: "2. Quiénes lo usan",
      blocks: [
        { type: "ul", items: [
          "Visitantes: buscan terapeutas sin crear cuenta y sin dar su nombre ni su mail.",
          "Terapeutas: crean una cuenta con su mail, completan un perfil y, una vez aprobado, aparecen en las búsquedas.",
        ] },
        { type: "p", text: "Para crear una cuenta hay que ser mayor de edad." },
      ],
    },
    {
      id: "que-no-es",
      title: "3. Lo que el sitio no es",
      blocks: [
        { type: "ul", items: [
          "No presta servicios de salud ni de terapia: los presta cada terapeuta, por su cuenta y bajo su responsabilidad.",
          "No da consejo médico ni recomienda una terapia en particular. No garantiza resultados.",
          "No verifica títulos, formación ni habilitaciones de los terapeutas. Que un perfil esté publicado significa que cumplió las reglas de contenido de estos términos, no que el sitio avale a la persona o a su práctica.",
          "Las terapias del directorio son complementarias y no reemplazan la atención médica ni psicológica. Ante una enfermedad o un malestar, consultá a un profesional de la salud habilitado.",
        ] },
      ],
    },
    {
      id: "cuenta",
      title: "4. La cuenta del terapeuta",
      blocks: [
        { type: "ul", items: [
          "Se accede con un enlace de un solo uso enviado al mail, que debe ser tuyo y estar verificado.",
          "Cada persona tiene una sola ficha. No compartas tu acceso con otras personas.",
          "Los datos que cargues deben ser verdaderos y mantenerse al día.",
        ] },
      ],
    },
    {
      id: "perfil",
      title: "5. El perfil y su revisión",
      blocks: [
        { type: "p", text: "Ningún perfil es público sin aprobación previa. Revisamos el alta y cada cambio antes de publicarlo; los cambios de contacto también pasan por revisión." },
        { type: "p", text: `Los plazos objetivo de revisión son de ${REVIEW_BUSINESS_DAYS.firstSubmission} días hábiles para un alta, ${REVIEW_BUSINESS_DAYS.change} para un cambio y ${REVIEW_BUSINESS_DAYS.priority} para una revisión prioritaria. Son objetivos, no una garantía.` },
        { type: "p", text: "Podemos rechazar un perfil, pausarlo o suspenderlo, siempre con un motivo registrado. Un perfil puede mostrar hasta " + MAX_THERAPIES_PER_PROFILE + " terapias." },
      ],
    },
    {
      id: "prohibido",
      title: "6. Contenido que no se acepta",
      blocks: [
        { type: "ul", items: [
          "Promesas de cura o de resultados, y afirmaciones de que se trata, se previene o se cura una enfermedad.",
          "Pedir o sugerir que se abandone o se evite un tratamiento médico.",
          "Datos de pacientes o de otras personas sin su autorización, o cualquier dato de salud de terceros.",
          "Contenido ilícito, discriminatorio, engañoso o que suplante a otra persona; publicidad ajena al servicio ofrecido; correo no deseado.",
          "Fotos de las que no tengas derecho de uso.",
        ] },
        { type: "p", text: "El enlace a tu página web, si lo cargás, se revisa junto con el perfil y debe cumplir las mismas reglas." },
      ],
    },
    {
      id: "precios",
      title: "7. Precios",
      blocks: [
        { type: "p", text: `Cargar tarifas es opcional. Se muestran como un valor \"desde\" por terapia, con la fecha en que el terapeuta las confirmó. Se consideran al día durante ${RATES_VALIDITY_MONTHS} meses desde esa fecha; pasado ese plazo se siguen mostrando con la fecha y un aviso de que pueden haber cambiado.` },
        { type: "p", text: "El precio final y las condiciones se acuerdan directamente entre el terapeuta y la persona. El sitio no cobra ni intermedia pagos." },
      ],
    },
    {
      id: "contacto",
      title: "8. Contacto y uso responsable",
      blocks: [
        { type: "p", text: "El teléfono y el mail de un terapeuta se muestran solo cuando el visitante lo pide con el botón correspondiente, y solo para comunicarse por una terapia. Está prohibido juntar datos de contacto de forma masiva o automática, usarlos para enviar publicidad o venderlos." },
        { type: "p", text: "Para evitar abusos hay límites de uso y verificaciones anti-bots; si se superan, el sitio puede dejar de mostrar contactos por un tiempo." },
      ],
    },
    {
      id: "gratuidad",
      title: "9. Gratuidad y cambios futuros",
      blocks: [
        { type: "p", text: "Hoy el sitio es gratuito para visitantes y terapeutas. Si en el futuro se ofrecen servicios opcionales, se informará con anticipación y no se cobrará nada sin aceptación expresa." },
      ],
    },
    {
      id: "denuncias-baja",
      title: "10. Denuncias y baja",
      blocks: [
        { type: "p", text: "Cualquier persona puede denunciar un perfil. Las denuncias las revisa el responsable del sitio, que puede suspender el perfil con un motivo registrado." },
        { type: "p", text: "El terapeuta puede eliminar su perfil y su cuenta cuando quiera. Se borran sus datos, salvo lo que la política de privacidad indica que se conserva." },
      ],
    },
    {
      id: "contenido-licencia",
      title: "11. Tu contenido",
      blocks: [
        { type: "p", text: "Seguís siendo titular de lo que cargás. Nos autorizás, de forma limitada y gratuita, a mostrarlo en el sitio mientras tu perfil esté publicado." },
      ],
    },
    {
      id: "responsabilidad",
      title: "12. Responsabilidad",
      blocks: [
        { type: "p", text: "La relación entre un terapeuta y quien lo consulta es ajena al sitio. En la medida que la ley lo permita, el sitio no responde por la atención que brinde un terapeuta ni por la veracidad de lo que publique, y no garantiza que el servicio esté disponible sin interrupciones. Esto no limita los derechos que la ley reconozca a los consumidores." },
      ],
    },
    {
      id: "cambios",
      title: "13. Cambios en estos términos",
      blocks: [
        { type: "p", text: "Cada versión tiene un código y una fecha. Si el cambio es sustancial, se pedirá a los terapeutas que lo acepten de nuevo." },
      ],
    },
    {
      id: "ley",
      title: "14. Ley aplicable",
      blocks: [
        { type: "p", text: "Estos términos se rigen por las leyes de la República Argentina. Se respetan los derechos que la legislación de cada país reconozca a las personas consumidoras." },
      ],
    },
  ],
};
