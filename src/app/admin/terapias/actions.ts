"use server";

// The two things an administrator does with the therapy catalog: add a therapy, and hide / show one. Never deletes. The database decides
// who may (is_admin() inside each function), checks every value again and leaves the trace in the audit log; this code only reads the
// form, explains the refusal and expires the cached therapy list so the change shows right away.
// Las dos cosas que hace un administrador con el catálogo de terapias: agregar una, y ocultar / mostrar una. Nunca borra. La base decide
// quién puede (is_admin() dentro de cada función), vuelve a revisar cada valor y deja el registro en la auditoría; este código solo lee
// el formulario, explica el rechazo y vence la lista de terapias en caché para que el cambio se vea enseguida.

import { updateTag } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin/guard";
import { THERAPIES_CACHE_TAG } from "@/lib/catalog-cache";
import { explainTherapyError, readAddTherapyForm } from "@/lib/admin/therapy-admin";

export type ActionState = { status: "idle" | "error"; message: string };
const fail = (message: string): ActionState => ({ status: "error", message });

export async function addTherapy(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase } = await requireAdmin();
  const parsed = readAddTherapyForm(formData);
  if (!parsed.ok) return fail(parsed.message);
  const { name, shortName, code, active } = parsed.value;

  const result = await supabase.rpc("admin_add_therapy", {
    p_code: code,
    p_name: name,
    p_is_active: active,
    // left out when empty: the function's default (no short name) applies / se omite si está vacío: rige el valor por defecto de la función
    ...(shortName === null ? {} : { p_short_name: shortName }),
  });
  if (result.error) {
    console.error(`admin_add_therapy failed / falló admin_add_therapy: ${result.error.code ?? "unknown"}`);
    return fail(explainTherapyError(result.error));
  }
  updateTag(THERAPIES_CACHE_TAG);
  redirect("/admin/terapias?resultado=agregada");
}

export async function setTherapyActive(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase } = await requireAdmin();
  const rawId = String(formData.get("therapyId") ?? "");
  const therapyId = /^[1-9][0-9]{0,8}$/.test(rawId) ? Number(rawId) : null;
  const wanted = formData.get("active");
  if (therapyId === null || (wanted !== "true" && wanted !== "false")) return fail("Pedido inválido.");

  const result = await supabase.rpc("admin_set_therapy_active", { p_therapy_id: therapyId, p_is_active: wanted === "true" });
  if (result.error) {
    console.error(`admin_set_therapy_active failed / falló admin_set_therapy_active: ${result.error.code ?? "unknown"}`);
    return fail(explainTherapyError(result.error));
  }
  updateTag(THERAPIES_CACHE_TAG);
  redirect("/admin/terapias");
}
