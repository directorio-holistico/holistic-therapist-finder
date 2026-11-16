"use server";

// Uploads the therapist's NEW photo to the private "pending" bucket. The profile is NOT changed here: the photo travels inside the
// draft revision and only goes public when the administrator approves it. The path is built here from the profile of the logged-in
// person; nothing about it comes from the browser.
// Sube la foto NUEVA del terapeuta al bucket privado "pendiente". Acá NO se cambia el perfil: la foto viaja dentro de la revisión
// borrador y solo se hace pública cuando la aprueba el administrador. La ruta se arma acá con el perfil de la persona ingresada;
// nada de ella viene del navegador.

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { requirePassword } from "@/lib/auth/password-gate";
import { processPhoto } from "@/lib/photo-process";
import {
  isPendingPhotoPath, PHOTO_CONSENT_VERSION, PHOTO_MAX_UPLOAD_BYTES, pendingPhotoPath, type PhotoErrorCode,
} from "@/lib/photo-rules";
import { pendingPhotoUrl, removeOtherPendingPhotos, removePendingPhoto, savePendingPhoto } from "@/lib/photo-storage";
import { createServerSupabase } from "@/lib/supabase/server-client";

export type UploadPhotoResult = { ok: true; path: string; previewUrl: string | null } | { ok: false; error: PhotoErrorCode };
const fail = (error: PhotoErrorCode): UploadPhotoResult => ({ ok: false, error });

export async function uploadPhoto(formData: FormData): Promise<UploadPhotoResult> {
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/ingresar");
  await requirePassword(supabase);

  // 1) What the browser sent / Lo que mandó el navegador
  if (formData.get("consent") !== "on") return fail("consent");
  const file = formData.get("photo");
  if (!(file instanceof Blob) || file.size === 0 || file.size > PHOTO_MAX_UPLOAD_BYTES) return fail("size");

  // 2) The profile of the logged-in person, with their own session (RLS). An administrator can read every profile: filter by person.
  // 2) El perfil de la persona ingresada, con su propia sesión (RLS). Un administrador puede leer todos los perfiles: se filtra por persona.
  const person = await supabase.from("people").select("id").eq("auth_user_id", auth.user.id).maybeSingle();
  if (person.error || !person.data) return fail("session");
  const profile = await supabase.from("therapist_profiles").select("id, status_id").eq("person_id", person.data.id).maybeSingle();
  if (profile.error || !profile.data) return fail("session");
  const status = await supabase.from("profile_statuses").select("code").eq("id", profile.data.status_id).maybeSingle();
  if (status.data?.code === "suspended" || status.data?.code === "erased") return fail("blocked");
  const open = await supabase.from("profile_revisions").select("status_id").eq("profile_id", profile.data.id).is("closed_at", null).maybeSingle();
  if (open.error) return fail("storage");
  if (open.data) {
    const revisionStatus = await supabase.from("revision_statuses").select("code").eq("id", open.data.status_id).maybeSingle();
    if (revisionStatus.data?.code !== "draft") return fail("locked");
  }

  // 3) Check and re-encode the picture (a real image, a sensible size, no metadata) / Comprobar y recodificar (imagen real, tamaño razonable, sin metadatos)
  const processed = await processPhoto(Buffer.from(await file.arrayBuffer()));
  if (!processed.ok) return fail(processed.reason);

  // 4) The consent, as legal evidence (person, text version, date) / El consentimiento, como evidencia legal (persona, versión del texto, fecha)
  const consent = await supabase.rpc("set_photo_consent", { p_value: true, p_version: PHOTO_CONSENT_VERSION });
  if (consent.error) {
    console.error(`set_photo_consent failed / falló set_photo_consent: ${consent.error.code ?? "unknown"}`);
    return fail("storage");
  }

  // 5) Save in the private bucket under a path made here; then keep only this one pending file for the profile
  // 5) Guardar en el bucket privado con una ruta armada acá; luego dejar solo este archivo pendiente del perfil
  const path = pendingPhotoPath(profile.data.id, randomUUID());
  if (!path || !isPendingPhotoPath(path, profile.data.id)) return fail("storage");
  if (!(await savePendingPhoto(path, processed.jpeg))) return fail("storage");
  await removeOtherPendingPhotos(profile.data.id, path);

  return { ok: true, path, previewUrl: await pendingPhotoUrl(path) };
}

// "Use another photo / Discard": deletes the pending file the browser names, but ONLY if it is a pending path of the own profile.
// "Usar otra foto / Descartar": borra el archivo pendiente que nombra el navegador, pero SOLO si es una ruta pendiente del propio perfil.
export async function discardPendingPhoto(path: string): Promise<boolean> {
  const supabase = await createServerSupabase();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return false;
  const person = await supabase.from("people").select("id").eq("auth_user_id", auth.user.id).maybeSingle();
  if (!person.data) return false;
  const profile = await supabase.from("therapist_profiles").select("id").eq("person_id", person.data.id).maybeSingle();
  if (!profile.data || !isPendingPhotoPath(path, profile.data.id)) return false;
  return removePendingPhoto(path);
}
