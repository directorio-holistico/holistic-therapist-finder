import { CONTROLLER_NAME, RETENTION } from "./facts";
import type { LegalDocument } from "./types";

export const PRIVACY: LegalDocument = {
  code: "privacy",
  slug: "privacidad",
  title: "Política de privacidad",
  summary: "Qué datos guardamos, para qué, por cuánto tiempo, con quién los compartimos y cómo ejercer tus derechos.",
  sections: [
    {
      id: "responsable",
      title: "1. Quién es el responsable",
      blocks: [
        { type: "p", text: `El responsable del tratamiento de los datos es ${CONTROLLER_NAME}, titular de Faro Holístico. Los datos de contacto y el domicilio figuran al final de esta página.` },
      ],
    },
    {
      id: "visitantes",
      title: "2. Si solo buscás un terapeuta",
      blocks: [
        { type: "p", text: "No necesitás cuenta y no te pedimos nombre, mail ni ningún dato de salud. Esto es lo único que registramos de una visita:" },
        { type: "ul", items: [
          `Búsquedas sin resultado: guardamos la terapia, la zona, el modo de atención y la fecha, sin tu dirección ni ningún identificador, para saber qué falta en el directorio. Se conservan ${RETENTION.unmetSearchesMonths} meses.`,
          `Cuando pedís ver un contacto: guardamos que se vio el contacto de un perfil y la fecha, sin ningún dato tuyo. Se conserva ${RETENTION.contactRevealsMonths} meses.`,
          `Protección contra abusos: para limitar pedidos repetidos guardamos, durante ${RETENTION.rateLimitDays} días, una huella irreversible calculada con una clave secreta a partir de tu dirección de red; la dirección en sí no se guarda. Al pedir un contacto, esa dirección se envía al servicio de verificación anti-bots que usamos (ver el apartado de proveedores).`,
        ] },
      ],
    },
    {
      id: "terapeutas",
      title: "3. Si sos terapeuta",
      blocks: [
        { type: "p", text: "Guardamos lo que cargás para tu cuenta y tu perfil:" },
        { type: "ul", items: [
          "Cuenta: nombre completo y mail (para ingresar y contactarte).",
          "Perfil: nombre que se muestra, foto (opcional), ciudad, zona o barrio (opcional), frase de presentación, año de inicio de tu práctica, terapias, idiomas, modos de atención (presencial o a distancia), formato (individual o grupal), duración aproximada y tarifas (opcionales).",
          "Contacto: teléfono (obligatorio), mail y página web (opcionales).",
          "Registros: las versiones de los documentos legales que aceptaste y cuándo, las decisiones de moderación (quién, cuándo y por qué) y un registro de auditoría con quién cambió qué y cuándo, que guarda solo los nombres de los campos cambiados y no sus valores personales.",
        ] },
        { type: "p", text: `El registro de auditoría se conserva ${RETENTION.auditLogMonths} meses.` },
      ],
    },
    {
      id: "publico",
      title: "4. Qué se muestra públicamente",
      blocks: [
        { type: "p", text: "Una vez aprobado tu perfil se muestran: nombre de perfil, foto, país, región y ciudad (y la zona si la cargaste), terapias, frase de presentación, modos y formatos, idiomas, tarifas \"desde\" y tu página web. Nunca mostramos tu dirección." },
        { type: "p", text: "Tu teléfono y tu mail no aparecen en el perfil: se muestran únicamente cuando un visitante aprieta el botón para ver el contacto." },
      ],
    },
    {
      id: "salud",
      title: "5. Datos de salud",
      blocks: [
        { type: "p", text: "El sitio no pide ni guarda datos de salud de pacientes. A los terapeutas les pedimos que no incluyan datos de pacientes en su perfil." },
      ],
    },
    {
      id: "finalidades",
      title: "6. Para qué usamos los datos",
      blocks: [
        { type: "ul", items: [
          "Prestar el servicio: mostrar tu perfil y conectar a los visitantes con vos.",
          "Moderar: revisar perfiles y denuncias para que no haya promesas de cura ni contenido prohibido.",
          "Mantener el sitio seguro y evitar abusos.",
          "Saber qué terapias y zonas busca la gente y no están cubiertas, con datos sin identificar.",
          "Enviarte ofertas de otros servicios propios, solo si lo aceptaste de forma opcional (ver el apartado siguiente).",
        ] },
      ],
    },
    {
      id: "ofertas",
      title: "7. Ofertas de otros servicios (opcional)",
      blocks: [
        { type: "p", text: "En el alta podés aceptar, de forma opcional, que el responsable te envíe por mail ofertas de otros servicios propios, por ejemplo un sistema de turnos. La casilla viene desmarcada. Podés retirar el consentimiento cuando quieras desde tu panel, sin consecuencias para tu perfil." },
      ],
    },
    {
      id: "proveedores",
      title: "8. Con quién compartimos datos",
      blocks: [
        { type: "p", text: "No vendemos datos. Usamos proveedores que los tratan por nuestra cuenta para que el sitio funcione:" },
        { type: "ul", items: [
          "Supabase: base de datos e ingreso con enlace por mail. La base está alojada en São Paulo, Brasil.",
          "Vercel: alojamiento del sitio.",
          "Un proveedor de envío de correo para los enlaces de ingreso (se informará su nombre cuando esté definido).",
          "Cloudflare (servicio Turnstile): verificación anti-bots al pedir un contacto; recibe la dirección de red del visitante.",
        ] },
        { type: "p", text: "Estos proveedores pueden tratar datos fuera de tu país. Para el caso de transferencias internacionales nos apoyamos en las condiciones contractuales de cada proveedor." },
      ],
    },
    {
      id: "plazos",
      title: "9. Cuánto tiempo guardamos los datos",
      blocks: [
        { type: "ul", items: [
          "Cuenta y perfil: mientras tu perfil exista. Si lo eliminás, se borran tu perfil, contactos, terapias, tarifas, foto y revisiones, y tu ficha queda anonimizada (sin nombre ni mail).",
          `Tras una eliminación conservamos ${RETENTION.erasureFingerprintMonths} meses una huella irreversible de tu mail y de tu teléfono: no permite recuperar el dato y sirve para detectar a quien se elimina y vuelve a registrarse para evitar una decisión de moderación. También quedan el historial de aceptaciones y los registros de moderación, ya sin datos personales.`,
          `Denuncias cerradas: ${RETENTION.closedReportsMonths} meses. Las abiertas se conservan hasta cerrarse. Si una denuncia incluye un mail de contacto opcional, se guarda hasta ese plazo.`,
          `Búsquedas sin resultado y contactos vistos: ${RETENTION.unmetSearchesMonths} y ${RETENTION.contactRevealsMonths} meses, respectivamente.`,
          `Huellas contra abusos: ${RETENTION.rateLimitDays} días. Registro de auditoría: ${RETENTION.auditLogMonths} meses.`,
        ] },
      ],
    },
    {
      id: "derechos",
      title: "10. Tus derechos",
      blocks: [
        { type: "p", text: "Podés pedir acceso a tus datos, que los corrijamos o actualicemos, que los suprimamos, y retirar tu consentimiento. Como terapeuta podés editar tu perfil y eliminarlo desde tu panel. Para cualquier otro pedido, escribinos al contacto indicado al final." },
        { type: "p", text: "Si no estás conforme con la respuesta, podés reclamar ante la autoridad de protección de datos de tu país. En Argentina, el acceso gratuito a tus datos puede ejercerse a intervalos no inferiores a seis meses salvo interés legítimo acreditado, y la Agencia de Acceso a la Información Pública, como órgano de control de la Ley 25.326, atiende las denuncias y reclamos por incumplimientos." },
      ],
    },
    {
      id: "cookies",
      title: "11. Cookies",
      blocks: [
        { type: "p", text: "Solo usamos la cookie estrictamente necesaria para mantener tu sesión de terapeuta; no se puede leer desde scripts del navegador. No usamos cookies de publicidad ni de seguimiento, y los visitantes no reciben ninguna cookie de sesión." },
      ],
    },
    {
      id: "seguridad",
      title: "12. Seguridad",
      blocks: [
        { type: "p", text: "Aplicamos controles de acceso por roles en la base de datos, conexión cifrada, límites de uso y revisión de cambios. Ningún sistema es infalible: si ocurriera un incidente que afecte tus datos, te lo informaremos como corresponda." },
      ],
    },
    {
      id: "menores",
      title: "13. Menores de edad",
      blocks: [
        { type: "p", text: "El alta de terapeutas es solo para mayores de edad. El sitio no está dirigido a menores y no les pide datos." },
      ],
    },
    {
      id: "cambios",
      title: "14. Cambios en esta política",
      blocks: [
        { type: "p", text: "Cada versión tiene un código y una fecha. Si el cambio es sustancial, se lo informaremos a los terapeutas y se les pedirá aceptarlo de nuevo." },
      ],
    },
  ],
};
