// The ONLY place that touches the photo buckets. It uses the SECRET (service role) key, so it runs only on the server, with paths the
// server built itself (see photo-rules.ts): never a path that came from the browser. Every function answers true/false or a value,
// and writes nothing sensitive in the logs (no path, no person).
// El ÚNICO lugar que toca los buckets de fotos. Usa la clave SECRETA (service role), así que corre solo en el servidor, con rutas que
// armó el propio servidor (ver photo-rules.ts): nunca una ruta que venga del navegador. Cada función devuelve verdadero/falso o un
// valor, y no escribe nada sensible en los logs (ni ruta ni persona).

import "server-only";
import { PHOTO_BUCKET } from "@/lib/photo";
import { PHOTO_PENDING_BUCKET } from "@/lib/photo-rules";
import { getServerEnv } from "@/lib/server-env";
import { createServiceClient } from "@/lib/supabase/service-client";

const SIGNED_URL_SECONDS = 300;

const storage = () => createServiceClient(getServerEnv()).storage;
const logFailure = (step: string) => console.error(`photo storage failed / falló el almacenamiento de fotos: ${step}`);

// Saves a processed photo in the PRIVATE bucket. A path is never overwritten (every upload has its own id).
// Guarda una foto procesada en el bucket PRIVADO. Una ruta nunca se pisa (cada subida tiene su propio id).
export async function savePendingPhoto(path: string, jpeg: Buffer): Promise<boolean> {
  const { error } = await storage().from(PHOTO_PENDING_BUCKET).upload(path, jpeg, { contentType: "image/jpeg", upsert: false });
  if (error) logFailure("save pending");
  return !error;
}

export async function removePendingPhoto(path: string): Promise<boolean> {
  const { error } = await storage().from(PHOTO_PENDING_BUCKET).remove([path]);
  if (error) logFailure("remove pending");
  return !error;
}

// Keeps ONE pending photo per profile: deletes every other file in the profile's folder (leftovers of earlier uploads).
// Deja UNA foto pendiente por perfil: borra todo otro archivo de la carpeta del perfil (restos de subidas anteriores).
export async function removeOtherPendingPhotos(profileId: string, keepPath: string): Promise<void> {
  const bucket = storage().from(PHOTO_PENDING_BUCKET);
  const listed = await bucket.list(profileId, { limit: 100 });
  if (listed.error) {
    logFailure("list pending");
    return;
  }
  const others = (listed.data ?? []).map((file) => `${profileId}/${file.name}`).filter((path) => path !== keepPath);
  if (others.length > 0) {
    const removed = await bucket.remove(others);
    if (removed.error) logFailure("clean pending");
  }
}

// A short-lived address to LOOK at a pending photo (the editor preview, the administrator's review). null = the file is not there.
// Una dirección de corta vida para MIRAR una foto pendiente (vista previa del editor, revisión del administrador). null = el archivo no está.
export async function pendingPhotoUrl(path: string): Promise<string | null> {
  const bucket = storage().from(PHOTO_PENDING_BUCKET);
  // The file must really be there (a rejected or discarded proposal has its file deleted): signing a missing path can still succeed.
  // El archivo tiene que estar de verdad (una propuesta rechazada o descartada tiene su archivo borrado): firmar una ruta inexistente a veces anda igual.
  const slash = path.lastIndexOf("/");
  const listed = await bucket.list(path.slice(0, slash), { limit: 100, search: path.slice(slash + 1) });
  if (listed.error || !(listed.data ?? []).some((file) => file.name === path.slice(slash + 1))) return null;
  const { data, error } = await bucket.createSignedUrl(path, SIGNED_URL_SECONDS);
  return error || !data ? null : data.signedUrl;
}

// Approval, step 1: copies the pending photo to the PUBLIC bucket under the same path. Done BEFORE approving, so a failure here
// leaves the profile untouched. / Aprobación, paso 1: copia la foto pendiente al bucket PÚBLICO con la misma ruta. Se hace ANTES de
// aprobar, así un fallo acá deja el perfil intacto.
export async function copyPendingToPublic(path: string): Promise<boolean> {
  const client = storage();
  const downloaded = await client.from(PHOTO_PENDING_BUCKET).download(path);
  if (downloaded.error || !downloaded.data) {
    logFailure("download pending");
    return false;
  }
  const bytes = Buffer.from(await downloaded.data.arrayBuffer());
  const uploaded = await client.from(PHOTO_BUCKET).upload(path, bytes, { contentType: "image/jpeg", upsert: true });
  if (uploaded.error) logFailure("copy to public");
  return !uploaded.error;
}

export async function removePublicPhoto(path: string): Promise<boolean> {
  const { error } = await storage().from(PHOTO_BUCKET).remove([path]);
  if (error) logFailure("remove public");
  return !error;
}
