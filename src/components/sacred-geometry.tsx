// Decorative "flower of life" pattern. Hidden from screen readers. / Patrón decorativo "flor de la vida". Oculto para lectores de pantalla.
const R = 100;

function centers(): Array<[number, number]> {
  const points: Array<[number, number]> = [[0, 0]];
  for (let i = 0; i < 6; i++) {
    const a = (Math.PI / 3) * i;
    points.push([R * Math.cos(a), R * Math.sin(a)]);
    points.push([2 * R * Math.cos(a), 2 * R * Math.sin(a)]);
    const b = a + Math.PI / 6;
    points.push([R * Math.sqrt(3) * Math.cos(b), R * Math.sqrt(3) * Math.sin(b)]);
  }
  return points;
}

export function SacredGeometry({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      focusable="false"
      viewBox="-340 -340 680 680"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
    >
      {centers().map(([x, y], i) => (
        <circle key={i} cx={x.toFixed(2)} cy={y.toFixed(2)} r={R} />
      ))}
      <circle r={3 * R} />
      <circle r={3 * R + 12} />
    </svg>
  );
}
