// Icons for the links of a profile (web and social networks), from Bootstrap Icons (MIT license, one colour: they follow the
// text colour, so they work in light and dark mode). Decoration: the link carries its own text label. The marks belong to
// their owners; each network's brand rules apply to their use.
// Íconos para los enlaces de un perfil (web y redes), de Bootstrap Icons (licencia MIT, de un solo color: siguen el color del
// texto, así que sirven en modo claro y oscuro). Son decoración: el enlace lleva su propio texto. Las marcas son de sus
// dueños; para usarlas valen las reglas de marca de cada red.

import { Facebook, Globe, Instagram, Tiktok, Whatsapp, Youtube } from "react-bootstrap-icons";
import type { ProfileLinkKind } from "@/lib/profile-detail";

export function SocialIcon({ kind, size = 20 }: { kind: ProfileLinkKind | "whatsapp"; size?: number }) {
  const props = { size, "aria-hidden": true, focusable: false } as const;
  switch (kind) {
    case "instagram":
      return <Instagram {...props} />;
    case "facebook":
      return <Facebook {...props} />;
    case "tiktok":
      return <Tiktok {...props} />;
    case "youtube":
      return <Youtube {...props} />;
    case "whatsapp":
      return <Whatsapp {...props} />;
    default:
      return <Globe {...props} />;
  }
}
