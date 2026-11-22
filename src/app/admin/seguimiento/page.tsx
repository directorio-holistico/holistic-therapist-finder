// Therapists who need a nudge: rejected and silent, or a draft never sent. Read-only. / Terapeutas a los que hay que escribirles:
// rechazados sin respuesta, o con un borrador sin enviar. Solo lectura.

import { Suspense } from "react";
import { requireAdmin } from "@/lib/admin/guard";
import { loadFollowUpItems, loadFollowUpStubs } from "@/lib/admin/followup";
import { elapsedLabel, type FollowUpItem } from "@/lib/admin/followup-view";
import { formatDate } from "@/lib/format";

const PROFILE_STATUS: Record<string, string> = {
  unpublished: "Todavía sin perfil publicado",
  published: "Ya tiene un perfil publicado (lo rechazado es un cambio)",
  suspended: "Perfil suspendido",
  withdrawn: "Perfil dado de baja",
};

function Card({ item }: { item: FollowUpItem }) {
  const verb = item.kind === "rejected" ? "Rechazada" : "Borrador creado";
  // Closed by default so many therapists fit on the screen; open it to see the detail. / Cerrado por defecto para ver varios a la vez.
  return (
    <li className="rounded-xl border border-linea bg-superficie">
      <details>
        <summary className="flex min-h-11 cursor-pointer items-center px-5 py-3 text-tinta focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento">
          <span>
            <span className="font-display text-lg font-semibold">{item.name}</span>
            <span className="text-apagado">
              {" - "}
              {verb} el {formatDate(item.date) ?? "—"} · {elapsedLabel(item.days)}
            </span>
          </span>
        </summary>
        <div className="border-t border-linea px-5 pb-5 pt-3">
          {item.profileStatus && <p className="text-sm text-apagado">{PROFILE_STATUS[item.profileStatus] ?? item.profileStatus}</p>}
          {item.reason && (
            <p className="mt-2 whitespace-pre-line text-tinta">
              <span className="font-medium">Motivo: </span>
              {item.reason}
            </p>
          )}
          <div className="mt-3 grid gap-1 text-sm text-tinta">
            {item.phone ? (
              <p>
                <span className="font-medium">Teléfono: </span>
                {item.phone.text}
                {item.phone.whatsapp ? " (WhatsApp)" : ""}
                {item.phone.whatsappLink && (
                  <>
                    {" · "}
                    <a
                      href={item.phone.whatsappLink}
                      target="_blank"
                      rel="noopener noreferrer"
                      aria-label={`Abrir WhatsApp con ${item.name}`}
                      className="text-acento underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
                    >
                      Abrir WhatsApp
                    </a>
                  </>
                )}
              </p>
            ) : (
              <p className="text-apagado">No cargó teléfono.</p>
            )}
            {item.email && (
              <p>
                <span className="font-medium">Mail de la cuenta: </span>
                {item.email}
              </p>
            )}
          </div>
        </div>
      </details>
    </li>
  );
}

function Section({ title, empty, items }: { title: string; empty: string; items: FollowUpItem[] }) {
  return (
    <section className="mt-6">
      <h2 className="font-display text-2xl font-semibold text-tinta">
        {title} <span className="text-apagado">({items.length})</span>
      </h2>
      {items.length === 0 ? (
        <p className="mt-2 text-apagado">{empty}</p>
      ) : (
        <ul className="mt-3 grid gap-2">
          {items.map((item) => (
            <Card key={item.revisionId} item={item} />
          ))}
        </ul>
      )}
    </section>
  );
}

async function Lists() {
  const { supabase } = await requireAdmin();
  const stubs = await loadFollowUpStubs(supabase);
  const { rejected, drafts } = await loadFollowUpItems(supabase, stubs);
  return (
    <>
      {!stubs.complete && (
        <p role="status" className="mt-4 rounded-lg border border-aviso-borde bg-aviso-fondo p-3 text-aviso-texto">
          Se leyeron solo las últimas 10.000 revisiones: la lista puede estar incompleta.
        </p>
      )}
      <Section title="Rechazados sin respuesta" empty="No hay rechazos esperando una respuesta." items={rejected} />
      <Section title="Borradores sin enviar" empty="No hay borradores sin enviar." items={drafts} />
    </>
  );
}

export default function FollowUpPage() {
  return (
    <main>
      <h1 className="mt-6 font-display text-3xl font-semibold text-tinta">Seguimiento de terapeutas</h1>
      <p className="mt-2 text-apagado">
        Rechazados: la última revisión del perfil fue rechazada y no hay otra posterior. Borradores: la última revisión nunca se envió. Se ordenan del más antiguo al más nuevo. Tocá un nombre para ver el detalle.
      </p>
      <Suspense fallback={<p className="mt-4 text-apagado">Cargando…</p>}>
        <Lists />
      </Suspense>
    </main>
  );
}
