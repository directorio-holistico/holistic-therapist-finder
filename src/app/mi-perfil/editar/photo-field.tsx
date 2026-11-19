"use client";

// Photo field of the profile editor: choose a picture, move and zoom it inside a round window, tick the authorization, and send it.
// The picture is cut and shrunk HERE (canvas) before it travels; the server checks and re-encodes it again. Nothing is public until
// the administrator approves it.
// Campo de foto del editor: elegir una imagen, moverla y hacerle zoom dentro de una ventana redonda, tildar la autorización y enviarla.
// La imagen se recorta y achica ACÁ (canvas) antes de viajar; el servidor la vuelve a comprobar y recodificar. Nada es público hasta
// que lo apruebe el administrador.

import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { clamp, CROP_OUTPUT, CROP_VIEW, drawRect, normalizeCrop, ZOOM_MAX, ZOOM_MIN, type Crop } from "@/lib/photo-crop";
import { PHOTO_CONSENT_TEXT, PHOTO_ERRORS } from "@/lib/photo-rules";
import { discardPendingPhoto, uploadPhoto } from "./photo-actions";

type Props = {
  initialNew: string; // pending path already in the draft / ruta pendiente que ya está en el borrador
  initialRemove: boolean;
  initialPreviewUrl: string | null; // signed address of the pending photo / dirección firmada de la foto pendiente
  liveUrl: string | null; // photo public today / foto pública hoy
  lost?: boolean; // the photo of the proposal is gone: tell the person / la foto de la propuesta ya no está: avisarle
  disabled?: boolean;
  onEdit?: () => void; // the person changed the photo choice: the form has unsent changes / la persona cambió la foto: el formulario tiene cambios sin enviar
};

type Picked = { url: string; image: HTMLImageElement };
const STEP = 16;

export function PhotoField({ initialNew, initialRemove, initialPreviewUrl, liveUrl, lost, disabled, onEdit }: Props) {
  const [newPath, setNewPath] = useState(initialNew);
  const [removeCurrent, setRemoveCurrent] = useState(initialRemove);
  const [previewUrl, setPreviewUrl] = useState(initialPreviewUrl);
  const [picked, setPicked] = useState<Picked | null>(null);
  const [crop, setCrop] = useState<Crop>({ zoom: 1, x: 0, y: 0 });
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const drag = useRef<{ x: number; y: number; cx: number; cy: number } | null>(null);

  // frees the browser memory used by the chosen picture / libera la memoria del navegador usada por la imagen elegida
  useEffect(() => () => { if (picked) URL.revokeObjectURL(picked.url); }, [picked]);

  const shown = removeCurrent ? null : newPath ? previewUrl : liveUrl;

  function choose(file: File | undefined) {
    setMessage("");
    if (!file) return;
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => { setPicked({ url, image }); setCrop({ zoom: 1, x: 0, y: 0 }); };
    image.onerror = () => { URL.revokeObjectURL(url); setMessage(PHOTO_ERRORS.unreadable); };
    image.src = url;
  }

  const move = (next: Crop) => picked && setCrop(normalizeCrop(picked.image.naturalWidth, picked.image.naturalHeight, next));
  function onPointerDown(event: PointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = { x: event.clientX, y: event.clientY, cx: crop.x, cy: crop.y };
  }
  function onPointerMove(event: PointerEvent<HTMLDivElement>) {
    if (drag.current) move({ zoom: crop.zoom, x: drag.current.cx + event.clientX - drag.current.x, y: drag.current.cy + event.clientY - drag.current.y });
  }
  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const delta: Record<string, [number, number]> = { ArrowLeft: [-STEP, 0], ArrowRight: [STEP, 0], ArrowUp: [0, -STEP], ArrowDown: [0, STEP] };
    const step = delta[event.key];
    if (!step) return;
    event.preventDefault();
    move({ zoom: crop.zoom, x: crop.x + step[0], y: crop.y + step[1] });
  }

  async function send() {
    if (!picked) return;
    if (!consent) { setMessage(PHOTO_ERRORS.consent); return; }
    setBusy(true);
    setMessage("");
    try {
      const canvas = document.createElement("canvas");
      canvas.width = CROP_OUTPUT;
      canvas.height = CROP_OUTPUT;
      const context = canvas.getContext("2d");
      if (!context) { setMessage(PHOTO_ERRORS.unreadable); return; }
      // a JPEG has no transparency: without a background, transparent areas turn black / un JPEG no tiene transparencia: sin fondo, lo transparente queda negro
      context.fillStyle = "#ffffff";
      context.fillRect(0, 0, CROP_OUTPUT, CROP_OUTPUT);
      const rect = drawRect(picked.image.naturalWidth, picked.image.naturalHeight, crop);
      context.drawImage(picked.image, rect.dx, rect.dy, rect.dw, rect.dh);
      const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
      if (!blob) { setMessage(PHOTO_ERRORS.unreadable); return; }
      const data = new FormData();
      data.set("photo", blob, "photo.jpg");
      data.set("consent", "on");
      const result = await uploadPhoto(data);
      if (!result.ok) { setMessage(PHOTO_ERRORS[result.error]); return; }
      // the server already deleted any older pending file / el servidor ya borró los pendientes viejos
      setNewPath(result.path);
      setPreviewUrl(result.previewUrl);
      setRemoveCurrent(false);
      setPicked(null);
      setConsent(false);
      onEdit?.();
    } catch {
      setMessage(PHOTO_ERRORS.storage);
    } finally {
      setBusy(false);
    }
  }

  async function dropNew() {
    setBusy(true);
    await discardPendingPhoto(newPath);
    setNewPath("");
    setPreviewUrl(null);
    setBusy(false);
    onEdit?.();
  }

  const window = picked ? drawRect(picked.image.naturalWidth, picked.image.naturalHeight, crop, CROP_VIEW, CROP_VIEW) : null;

  return (
    <section className="grid gap-4" aria-labelledby="sec-foto">
      <h2 id="sec-foto" className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">Tu foto</h2>
      {/* these fields travel with the form: the path of the new pending photo and the wish to remove the current one */}
      <input type="hidden" name="photoNew" value={newPath} />
      {removeCurrent && <input type="hidden" name="photoRemove" value="on" />}

      {!picked && (
        <div className="flex items-center gap-4">
          <div className="size-24 shrink-0 overflow-hidden rounded-full bg-zinc-200 dark:bg-zinc-800">
            {/* eslint-disable-next-line @next/next/no-img-element -- address of a private or public Storage file / dirección de un archivo de Storage */}
            {shown ? <img src={shown} alt="Tu foto de perfil" className="size-full object-cover" /> : null}
          </div>
          <div className="grid gap-1 text-sm text-zinc-700 dark:text-zinc-300">
            {lost && !newPath && !removeCurrent && (
              <p role="status" className="rounded-md border border-amber-400 bg-amber-50 p-3 text-amber-900">Tu foto anterior no se pudo conservar. Subila de nuevo, por favor.</p>
            )}
            {newPath && <p role="status">Foto nueva lista, pero todavía no se envió. Apretá «Enviar a revisión» al final: la publicamos cuando la aprobemos.</p>}
            {removeCurrent && <p role="status">Marcaste quitar tu foto, pero todavía no se envió. Apretá «Enviar a revisión» al final: la quitamos cuando se apruebe.</p>}
            {!newPath && !removeCurrent && !liveUrl && <p>Todavía no tenés foto. Es opcional.</p>}
          </div>
        </div>
      )}

      {picked && window && (
        <div className="grid gap-3">
          <p className="text-sm text-zinc-700 dark:text-zinc-300">Arrastrá la foto (o usá las flechas) y ajustá el zoom hasta que quede bien dentro del círculo.</p>
          <div
            role="group" tabIndex={0} aria-label="Ventana de recorte: usá las flechas para mover la foto"
            onPointerDown={onPointerDown} onPointerMove={onPointerMove}
            onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }} onKeyDown={onKeyDown}
            className="relative mx-auto touch-none overflow-hidden rounded-full bg-zinc-300 outline-offset-4 focus-visible:outline-2"
            style={{ width: CROP_VIEW, height: CROP_VIEW, maxWidth: "100%" }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element -- local preview of the chosen file / vista previa local del archivo elegido */}
            <img src={picked.url} alt="" draggable={false} className="pointer-events-none absolute max-w-none select-none"
              style={{ left: window.dx, top: window.dy, width: window.dw, height: window.dh }} />
          </div>
          <label className="grid gap-1 text-sm text-zinc-800 dark:text-zinc-200">
            Zoom
            <input type="range" min={ZOOM_MIN} max={ZOOM_MAX} step={0.05} value={crop.zoom}
              onChange={(event) => move({ ...crop, zoom: clamp(Number(event.target.value), ZOOM_MIN, ZOOM_MAX) })} />
          </label>
          <label className="flex items-start gap-3 text-zinc-800 dark:text-zinc-200">
            <input type="checkbox" checked={consent} onChange={(event) => setConsent(event.target.checked)} className="mt-1 h-5 w-5" />
            <span>{PHOTO_CONSENT_TEXT}</span>
          </label>
          <div className="flex flex-wrap gap-3">
            <button type="button" onClick={send} disabled={busy || disabled} className="rounded-md bg-zinc-900 px-4 py-3 font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900">
              {busy ? "Subiendo…" : "Usar esta foto"}
            </button>
            <button type="button" onClick={() => { setPicked(null); setMessage(""); }} disabled={busy} className="rounded-md border border-zinc-400 px-4 py-3">Cancelar</button>
          </div>
        </div>
      )}

      {!picked && (
        <div className="flex flex-wrap gap-3">
          <label className="cursor-pointer rounded-md border border-zinc-400 px-4 py-3 font-medium text-zinc-900 dark:text-zinc-100">
            {shown ? "Cambiar foto" : "Elegir foto"}
            <input type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" disabled={busy || disabled}
              onChange={(event) => { choose(event.target.files?.[0]); event.target.value = ""; }} />
          </label>
          {newPath && <button type="button" onClick={dropNew} disabled={busy} className="rounded-md border border-zinc-400 px-4 py-3">Descartar foto nueva</button>}
          {!newPath && liveUrl && !removeCurrent && <button type="button" onClick={() => { setRemoveCurrent(true); onEdit?.(); }} className="rounded-md border border-zinc-400 px-4 py-3">Quitar foto</button>}
          {removeCurrent && <button type="button" onClick={() => { setRemoveCurrent(false); onEdit?.(); }} className="rounded-md border border-zinc-400 px-4 py-3">Mantener mi foto</button>}
        </div>
      )}
      <p className="text-sm text-zinc-600 dark:text-zinc-400">Usá una foto tuya, de frente. No se aceptan logos ni fotos de otras personas. La revisamos antes de publicarla.</p>
      {message && <p role="alert" className="text-sm text-red-700">{message}</p>}
    </section>
  );
}
