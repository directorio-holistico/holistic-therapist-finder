# Colores y tipografías / Colours and typefaces

Fuente única: `src/app/globals.css`. Los contrastes de texto los verifica `tests/brand-contrast.test.ts` (mínimo 4,5:1, WCAG 2.1 AA).
Single source: `src/app/globals.css`. Text contrasts are checked by `tests/brand-contrast.test.ts` (minimum 4.5:1, WCAG 2.1 AA).

| Par (texto sobre fondo) | Claro | Oscuro |
|---|---|---|
| tinta sobre fondo | 14,19 | 15,85 |
| tinta sobre superficie | 15,40 | 14,15 |
| apagado sobre fondo | 6,55 | 9,20 |
| apagado sobre superficie | 7,10 | 8,22 |
| acento sobre fondo | 5,46 | 9,96 |
| acento sobre superficie | 5,93 | 8,89 |
| texto de botón sobre botón | 14,19 | 9,96 |

- Claro: fondo `#FBF5EA`, superficie `#FFFFFF`, tinta `#26232F`, apagado `#5B5663`, acento `#8A5A00`, oro `#E9B949`.
- Oscuro: fondo `#0F1233`, superficie `#181C46`, tinta `#F5EFE0`, apagado `#B9B6CC`, acento y oro `#E9B949`.
- Los 12 puntos de color de la estrella y el oro de la geometría sagrada son decorativos (ocultos para lectores de pantalla): no llevan texto encima.
- Modo oscuro: lo elige el visitante (botón del pie), por defecto claro; se guarda en el navegador (`faro-tema`). No sigue la configuración del dispositivo.
- Tipografías (licencia SIL OFL 1.1, copias en esta carpeta): Fraunces (títulos) y DM Sans (texto), archivos locales en `src/app/fonts/`; no se llama a servidores de Google.
- Logo: archivos de `public/brand/` recortados y pasados a WebP desde los originales de Camino Doce Doce (fondo quitado por código; los "transparentes" recibidos no tenían canal alfa).
