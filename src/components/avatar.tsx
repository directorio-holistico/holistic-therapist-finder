import { starRingGradient } from "@/lib/brand";
import { initialsOf } from "@/lib/card-view";
import { getPublicEnv } from "@/lib/env";
import { photoPublicUrl } from "@/lib/photo";

// Avatar: the profile photo inside a ring with the 12 colours of the star. The initials are always drawn underneath, so a missing or
// broken photo still shows them (no JavaScript needed). Decorative: the name is written next to it.
// Avatar: la foto del perfil dentro de un aro con los 12 colores de la estrella. Las iniciales se dibujan siempre debajo, así una foto
// ausente o rota igual las muestra (sin JavaScript). Decorativo: el nombre está escrito al lado.
export function Avatar({ name, size = "md", photoPath = null }: { name: string; size?: "md" | "lg" | "xl"; photoPath?: string | null }) {
  const url = photoPublicUrl(getPublicEnv().supabaseUrl, photoPath);
  const px = size === "xl" ? 176 : size === "lg" ? 88 : 56;
  const box = size === "xl" ? "size-36 sm:size-44" : size === "lg" ? "size-24" : "size-16";
  const text = size === "xl" ? "text-5xl" : size === "lg" ? "text-3xl" : "text-xl";
  return (
    <span
      aria-hidden="true"
      className={`inline-flex shrink-0 items-center justify-center rounded-full p-1 ${box}`}
      style={{ background: starRingGradient() }}
    >
      <span className={`relative flex size-full items-center justify-center overflow-hidden rounded-full bg-superficie font-display font-semibold text-tinta ${text}`}>
        {initialsOf(name)}
        {url && (
          // Plain <img>: the file is already a small square (<= 512 px); no image optimiser needed. / <img> simple: el archivo ya es un cuadrado chico (<= 512 px); no hace falta optimizador.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt="" width={px} height={px} loading={size === "xl" ? "eager" : "lazy"} decoding="async" className="absolute inset-0 size-full rounded-full object-cover" />
        )}
      </span>
    </span>
  );
}
