// Math of the photo crop (move and zoom), apart from the screen so it can be tested. The picture is shown "covering" a square window
// of CROP_VIEW pixels; the therapist zooms (1x to 3x) and moves it, and the part inside the window becomes a CROP_OUTPUT square.
// Cuentas del recorte de la foto (mover y hacer zoom), separadas de la pantalla para poder probarlas. La imagen se muestra "cubriendo"
// una ventana cuadrada de CROP_VIEW píxeles; el terapeuta hace zoom (de 1x a 3x) y la mueve, y lo que queda dentro de la ventana
// pasa a ser un cuadrado de CROP_OUTPUT.

export const CROP_VIEW = 256; // side of the window on screen, in CSS pixels / lado de la ventana en pantalla, en píxeles CSS
export const CROP_OUTPUT = 600; // side of the picture sent to the server, in pixels / lado de la imagen que se manda al servidor, en píxeles
export const ZOOM_MIN = 1;
export const ZOOM_MAX = 3;

export type Crop = { zoom: number; x: number; y: number }; // x, y: shift of the picture centre from the window centre / desplazamiento del centro de la imagen respecto del centro de la ventana

export const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

// Size of the picture on screen at zoom 1: the shorter side exactly fills the window. / Tamaño de la imagen en pantalla con zoom 1: el lado corto llena justo la ventana.
export function baseScale(naturalWidth: number, naturalHeight: number, view = CROP_VIEW): number {
  const short = Math.min(naturalWidth, naturalHeight);
  return short > 0 ? view / short : 1;
}

// Keeps the picture covering the whole window (no empty edges) and the zoom inside its limits.
// Mantiene la imagen cubriendo toda la ventana (sin bordes vacíos) y el zoom dentro de sus límites.
export function normalizeCrop(naturalWidth: number, naturalHeight: number, crop: Crop, view = CROP_VIEW): Crop {
  const zoom = clamp(Number.isFinite(crop.zoom) ? crop.zoom : ZOOM_MIN, ZOOM_MIN, ZOOM_MAX);
  const scale = baseScale(naturalWidth, naturalHeight, view) * zoom;
  const maxX = Math.max(0, (naturalWidth * scale - view) / 2);
  const maxY = Math.max(0, (naturalHeight * scale - view) / 2);
  // "|| 0" turns a negative zero into a plain zero / "|| 0" convierte un cero negativo en cero común
  return { zoom, x: clamp(Number.isFinite(crop.x) ? crop.x : 0, -maxX, maxX) || 0, y: clamp(Number.isFinite(crop.y) ? crop.y : 0, -maxY, maxY) || 0 };
}

// Where to draw the whole picture on the output square (for canvas drawImage). / Dónde dibujar la imagen entera en el cuadrado de salida (para drawImage del canvas).
export function drawRect(naturalWidth: number, naturalHeight: number, crop: Crop, view = CROP_VIEW, output = CROP_OUTPUT) {
  const normalized = normalizeCrop(naturalWidth, naturalHeight, crop, view);
  const scale = baseScale(naturalWidth, naturalHeight, view) * normalized.zoom * (output / view);
  const width = naturalWidth * scale;
  const height = naturalHeight * scale;
  return { dx: output / 2 + normalized.x * (output / view) - width / 2, dy: output / 2 + normalized.y * (output / view) - height / 2, dw: width, dh: height };
}
