import Image from "next/image";
import { STAR_DOT_COLORS } from "@/lib/brand";

// Star of Camino Doce Doce with its ring of 12 coloured dots. Decorative: the brand name is written next to it.
// Estrella de Camino Doce Doce con su anillo de 12 puntos de color. Decorativa: el nombre está escrito al lado.
export function HeroStar() {
  return (
    <div aria-hidden="true" className="relative mx-auto size-40 sm:size-72">
      <div className="estrella-gira absolute inset-0">
        <Image
          src="/brand/estrella-claro.webp"
          alt=""
          width={640}
          height={640}
          preload
          className="absolute inset-0 size-full dark:hidden"
        />
        <Image
          src="/brand/estrella-oscuro.webp"
          alt=""
          width={640}
          height={640}
          preload
          className="absolute inset-0 hidden size-full dark:block"
        />
      </div>
      <ul className="absolute -inset-5">
        {STAR_DOT_COLORS.map((color, i) => {
          const angle = (Math.PI * 2 * i) / STAR_DOT_COLORS.length - Math.PI / 2 + Math.PI / 12;
          const left = 50 + 50 * Math.cos(angle);
          const top = 50 + 50 * Math.sin(angle);
          return (
            <li
              key={color}
              className="absolute size-3 -translate-x-1/2 -translate-y-1/2 rounded-full ring-1 ring-black/25"
              style={{ left: `${left}%`, top: `${top}%`, backgroundColor: color }}
            />
          );
        })}
      </ul>
    </div>
  );
}
