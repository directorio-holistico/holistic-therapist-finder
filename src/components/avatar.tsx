import { starRingGradient } from "@/lib/brand";
import { initialsOf } from "@/lib/card-view";

// Provisional avatar: initials inside a ring with the 12 colours of the star. Decorative: the name is written next to it.
// Avatar provisorio: iniciales dentro de un aro con los 12 colores de la estrella. Decorativo: el nombre está escrito al lado.
export function Avatar({ name, size = "md" }: { name: string; size?: "md" | "lg" }) {
  return (
    <span
      aria-hidden="true"
      className={`inline-flex shrink-0 items-center justify-center rounded-full p-1 ${size === "lg" ? "size-24" : "size-16"}`}
      style={{ background: starRingGradient() }}
    >
      <span className={`flex size-full items-center justify-center rounded-full bg-superficie font-display font-semibold text-tinta ${size === "lg" ? "text-3xl" : "text-xl"}`}>
        {initialsOf(name)}
      </span>
    </span>
  );
}
