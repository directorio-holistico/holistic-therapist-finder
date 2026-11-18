import type { InfoDocument } from "./types";

export const COOKIES: InfoDocument = {
  code: "cookies",
  slug: "cookies",
  title: "Política de cookies",
  summary: "Qué cookies usa el sitio, para qué y cómo borrarlas.",
  sections: [
    {
      id: "que-son",
      title: "1. Qué son las cookies",
      blocks: [
        { type: "p", text: "Una cookie es un archivo pequeño que el sitio guarda en tu navegador. Algunas son imprescindibles para que una función ande; otras sirven para medir o para mostrar publicidad." },
      ],
    },
    {
      id: "usamos",
      title: "2. Qué cookies usamos",
      blocks: [
        { type: "p", text: "Solo usamos cookies estrictamente necesarias, y únicamente cuando un terapeuta ingresa a su cuenta:" },
        { type: "ul", items: [
          "Sesión del terapeuta (nombre con la forma «sb-…-auth-token», a veces partida en trozos «.0», «.1»): mantiene tu sesión abierta. Es propia del sitio, no la pueden leer los scripts del navegador (httpOnly), no se envía a otros sitios (SameSite Lax) y en el sitio publicado viaja solo por conexión cifrada.",
          "Ingreso por enlace (nombre terminado en «code-verifier»): es temporal y se guarda mientras se completa el ingreso con el enlace que llega por mail.",
        ] },
        { type: "p", text: "Los visitantes que solo buscan terapeutas no reciben ninguna cookie de sesión." },
        { type: "p", text: "Cuando pedís ver un contacto o enviás una denuncia se carga la verificación anti-bots de Cloudflare (Turnstile). Es un servicio de un tercero: si guardara algo en tu navegador, lo haría para esa verificación y se rige por su propia política." },
      ],
    },
    {
      id: "no-usamos",
      title: "3. Lo que no usamos",
      blocks: [
        { type: "p", text: "No usamos cookies de publicidad, de analítica ni de seguimiento, y no hay herramientas de terceros que midan tu navegación." },
      ],
    },
    {
      id: "consentimiento",
      title: "4. Consentimiento",
      blocks: [
        { type: "p", text: "Las cookies estrictamente necesarias no requieren consentimiento, por eso el sitio no muestra un aviso de cookies. Si algún día se agregaran otras, se pedirá tu consentimiento antes de usarlas y se actualizará esta página." },
      ],
    },
    {
      id: "borrar",
      title: "5. Cómo borrarlas o bloquearlas",
      blocks: [
        { type: "p", text: "Podés borrar o bloquear las cookies desde la configuración de tu navegador. Si bloqueás la de sesión, un terapeuta no podrá ingresar a su cuenta; la búsqueda y la consulta de perfiles siguen funcionando igual." },
      ],
    },
    {
      id: "cambios",
      title: "6. Cambios en esta política",
      blocks: [
        { type: "p", text: "Publicamos cada versión en esta página, con un código y una fecha." },
      ],
    },
  ],
};
