import { flagSrc } from "@/lib/card-view";

// Small flag of the therapist's country, placed by the parent (top right of a card). Nothing is drawn when there is no flag file.
// The country name is the accessible text, so the meaning does not depend on the colours.
// Banderita del país del terapeuta; la ubica el padre (arriba a la derecha de una tarjeta). Si no hay archivo, no dibuja nada.
// El nombre del país es el texto accesible, así el significado no depende de los colores.
export function CountryFlag({ iso, name, size = "md" }: { iso: string | null; name: string | null; size?: "md" | "lg" }) {
  const src = flagSrc(iso);
  if (!src) return null;
  const [w, h, box] = size === "lg" ? [40, 30, "h-[30px] w-10"] : [32, 24, "h-6 w-8"];
  return (
    // Plain <img>: a small static SVG from /public. / <img> simple: un SVG chico y estático de /public.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={name ?? ""} title={name ?? undefined} width={w} height={h} loading="lazy" decoding="async" className={`absolute right-4 top-4 rounded-sm object-cover ring-1 ring-linea ${box}`} />
  );
}
