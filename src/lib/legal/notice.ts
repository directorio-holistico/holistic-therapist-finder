import { CONTROLLER_NAME } from "./facts";
import type { InfoDocument } from "./types";

export const NOTICE: InfoDocument = {
  code: "legal_notice",
  slug: "aviso-legal",
  title: "Aviso legal",
  summary: "Quién opera el sitio, qué es y qué no es, y cómo se relacionan los textos legales.",
  sections: [
    {
      id: "titular",
      title: "1. Quién opera el sitio",
      blocks: [
        { type: "p", text: `Faro Holístico es un directorio gratuito de terapeutas holísticos que opera ${CONTROLLER_NAME}. Los datos de contacto y el domicilio figuran al final de esta página.` },
      ],
    },
    {
      id: "objeto",
      title: "2. Qué es el sitio",
      blocks: [
        { type: "p", text: "El sitio permite buscar terapeutas por terapia y zona y ver sus datos de contacto. Solo crea esa conexión: no da turnos, no cobra, no guarda historias clínicas, no ofrece chat y no publica reseñas de pacientes." },
        { type: "p", text: "Los terapeutas publican sus propios perfiles y son responsables de lo que ofrecen. El sitio revisa los perfiles antes de publicarlos, pero no verifica títulos, formación ni habilitaciones." },
      ],
    },
    {
      id: "salud",
      title: "3. Aviso sobre salud",
      blocks: [
        { type: "p", text: "El contenido del sitio es informativo. Las terapias del directorio no son medicina ni tratamientos médicos: son complementarias y no reemplazan la atención médica ni psicológica. Ante una enfermedad o un malestar, consultá a un profesional de la salud habilitado. El sitio no garantiza resultados de ninguna terapia y ningún perfil puede prometer curas." },
      ],
    },
    {
      id: "propiedad",
      title: "4. Propiedad intelectual",
      blocks: [
        { type: "p", text: "El nombre «Faro Holístico», su logo y el diseño del sitio identifican a este servicio. El código fuente se publica con licencia MIT, que cubre el código y no el nombre, el logo ni los contenidos que cargan los terapeutas, que siguen siendo de sus titulares." },
      ],
    },
    {
      id: "responsabilidad",
      title: "5. Responsabilidad",
      blocks: [
        { type: "p", text: "En la medida que la ley lo permita, el sitio no responde por la atención que brinde un terapeuta, por la veracidad de lo que publique ni por los sitios a los que enlace. Los detalles están en los términos y condiciones de uso." },
      ],
    },
    {
      id: "ley",
      title: "6. Ley aplicable",
      blocks: [
        { type: "p", text: "Este aviso se rige por las leyes de la República Argentina, sin perjuicio de los derechos que la legislación de cada país reconozca a las personas consumidoras y a los titulares de datos personales." },
      ],
    },
    {
      id: "otros",
      title: "7. Otros textos legales",
      blocks: [
        { type: "p", text: "Este aviso se complementa con los términos y condiciones de uso, la política de privacidad y la política de cookies, que también están en la sección de legales." },
      ],
    },
    {
      id: "cambios",
      title: "8. Cambios en este aviso",
      blocks: [
        { type: "p", text: "Publicamos cada versión en esta página, con un código y una fecha." },
      ],
    },
  ],
};
