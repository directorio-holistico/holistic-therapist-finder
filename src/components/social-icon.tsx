// Icons for the links of a profile (web and social networks), from Bootstrap Icons (MIT license, one colour: they follow the
// text colour, so they work in light and dark mode). Decoration: the link carries its own text label. The marks belong to
// their owners; each network's brand rules apply to their use.
// Íconos para los enlaces de un perfil (web y redes), de Bootstrap Icons (licencia MIT, de un solo color: siguen el color del
// texto, así que sirven en modo claro y oscuro). Son decoración: el enlace lleva su propio texto. Las marcas son de sus
// dueños; para usarlas valen las reglas de marca de cada red.

import { Facebook, Globe, Instagram, Tiktok, Whatsapp, Youtube } from "react-bootstrap-icons";
import type { ProfileLinkKind } from "@/lib/profile-detail";

// Colour a link takes on hover/focus (the icon is one colour at rest). Full class names so Tailwind can see them.
// Color que toma el enlace al pasar el mouse o enfocar (en reposo el ícono es de un solo color). Clases completas para que Tailwind las vea.
export const SOCIAL_HOVER: Record<ProfileLinkKind, string> = {
  website: "hover:text-acento focus-visible:text-acento",
  instagram: "hover:text-[#E4405F] focus-visible:text-[#E4405F]",
  facebook: "hover:text-[#1877F2] focus-visible:text-[#1877F2]",
  tiktok: "hover:text-[#FE2C55] focus-visible:text-[#FE2C55]",
  youtube: "hover:text-[#FF0000] focus-visible:text-[#FF0000]",
};

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
