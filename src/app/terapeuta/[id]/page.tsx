// Public profile of a therapist. Everything the patient needs to know about the therapist, therapy by therapy. The phone and
// the mail are NOT here: they come with the contact reveal (next step, protected by ADR-0003).
// Perfil público de un terapeuta. Todo lo que el paciente necesita saber, terapia por terapia. El teléfono y el mail NO
// están acá: llegan con la revelación de contacto (paso siguiente, protegida por el ADR-0003).

import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ModeBadge } from "@/components/mode-icon";
import { formatDate, formatMoney } from "@/lib/format";
import { joinWithY, labelLanguage, labelRateAudience, labelSessionFormat } from "@/lib/labels";
import { loadPublicProfile, type ProfileDetail, type ProfileLinkKind, type TherapyDetail } from "@/lib/profile-detail";
import { createAnonClient } from "@/lib/supabase/anon-client";

export const metadata: Metadata = { title: "Perfil del terapeuta" };

type PageProps = { params: Promise<{ id: string }> };

const LINK_LABELS: Record<ProfileLinkKind, string> = {
  website: "Sitio web",
  instagram: "Instagram",
  facebook: "Facebook",
  tiktok: "TikTok",
  youtube: "YouTube",
};

function initialsOf(name: string): string {
  const letters = name.replace(/\[[^\]]*\]/g, "").trim().split(/\s+/).filter(Boolean);
  return ((letters[0]?.[0] ?? "") + (letters.length > 1 ? (letters[letters.length - 1]?.[0] ?? "") : "")).toUpperCase();
}

function TherapyBlock({ therapy }: { therapy: TherapyDetail }) {
  return (
    <li className="rounded-lg border border-zinc-300 p-4 dark:border-zinc-700">
      <h3 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">{therapy.name}</h3>
      {therapy.serviceModes.length > 0 && (
        <ul className="mt-2 flex list-none flex-wrap gap-2 p-0" aria-label="Modo de atención">
          {therapy.serviceModes.map((mode) => (
            <li key={mode}><ModeBadge mode={mode} /></li>
          ))}
        </ul>
      )}
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
        {[
          therapy.sessionFormats.length > 0 ? joinWithY(therapy.sessionFormats.map(labelSessionFormat)) : "",
          therapy.sessionMinutes ? `Sesión de ${therapy.sessionMinutes} min` : "",
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      {therapy.rates.length > 0 ? (
        <ul className="mt-2 list-none p-0 text-sm text-zinc-800 dark:text-zinc-200">
          {therapy.rates.map((rate) => (
            <li key={rate.audience}>
              {labelRateAudience(rate.audience)}: <span className="font-medium">{formatMoney(rate.amount, rate.currency)}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">Precio: consultar con el terapeuta.</p>
      )}
    </li>
  );
}

function RatesFreshness({ profile }: { profile: ProfileDetail }) {
  if (!profile.therapies.some((therapy) => therapy.rates.length > 0)) return null;
  const date = formatDate(profile.ratesConfirmedAt);
  return (
    <p className="mt-2 text-xs text-zinc-600 dark:text-zinc-400">
      {profile.ratesCurrent && date
        ? `Precios al día · confirmados el ${date}`
        : date
          ? `Precios del ${date}: pueden haber cambiado`
          : "Precios sin fecha de confirmación"}
    </p>
  );
}

function ProfileView({ profile }: { profile: ProfileDetail }) {
  return (
    <article>
      <header className="flex items-start gap-4">
        {/* Space for the photo: until photos exist (later step) a neutral circle with the initials. / Lugar para la foto: hasta que existan, un círculo neutro con las iniciales. */}
        <div
          aria-hidden="true"
          className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full bg-zinc-200 text-2xl font-semibold text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
        >
          {initialsOf(profile.displayName)}
        </div>
        <div>
          <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">{profile.displayName}</h1>
          {profile.isPinned && <p className="text-xs text-zinc-600 dark:text-zinc-400">Fundador del sitio</p>}
          {profile.headline && <p className="mt-1 text-zinc-800 dark:text-zinc-200">{profile.headline}</p>}
          {profile.place && <p className="mt-1 text-sm text-zinc-700 dark:text-zinc-300">{profile.place}</p>}
        </div>
      </header>

      {profile.therapies.length > 0 && (
        <section aria-labelledby="therapies-title" className="mt-8">
          <h2 id="therapies-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">Terapias</h2>
          <ul className="mt-3 grid list-none gap-4 p-0">
            {profile.therapies.map((therapy) => (
              <TherapyBlock key={therapy.therapyId} therapy={therapy} />
            ))}
          </ul>
          <RatesFreshness profile={profile} />
        </section>
      )}

      {(profile.languages.length > 0 || profile.practiceStartYear !== null) && (
        <section aria-labelledby="about-title" className="mt-8">
          <h2 id="about-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">Datos</h2>
          <ul className="mt-2 list-none p-0 text-zinc-800 dark:text-zinc-200">
            {profile.languages.length > 0 && <li>Idiomas: {profile.languages.map(labelLanguage).join(", ")}</li>}
            {profile.practiceStartYear !== null && <li>Atiende desde {profile.practiceStartYear}</li>}
          </ul>
        </section>
      )}

      <section aria-labelledby="contact-title" className="mt-8">
        <h2 id="contact-title" className="text-xl font-semibold text-zinc-900 dark:text-zinc-100">Contacto</h2>
        {profile.links.length > 0 && (
          <ul className="mt-2 list-none p-0 text-zinc-800 dark:text-zinc-200">
            {profile.links.map((link) => (
              <li key={link.kind}>
                {LINK_LABELS[link.kind]}:{" "}
                <a className="underline" href={link.href} target="_blank" rel="noopener noreferrer nofollow">{link.text}</a>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">
          El teléfono y el mail se podrán ver desde acá en el próximo paso del sitio.
        </p>
      </section>
    </article>
  );
}

async function ProfileContent({ params }: PageProps) {
  const { id } = await params;
  const profile = await loadPublicProfile(createAnonClient(), id);
  if (!profile) notFound();
  return <ProfileView profile={profile} />;
}

export default function ProfilePage({ params }: PageProps) {
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-8">
      <p className="mb-4">
        <Link className="underline" href="/buscar">← Volver a la búsqueda</Link>
      </p>
      <Suspense fallback={<p className="text-zinc-700 dark:text-zinc-300">Cargando el perfil…</p>}>
        <ProfileContent params={params} />
      </Suspense>
      <p className="mt-10 border-t border-zinc-300 pt-4 text-sm text-zinc-700 dark:border-zinc-700 dark:text-zinc-300">
        Este sitio solo conecta personas con terapeutas: no da turnos ni cobra, y no reemplaza la atención médica ni
        psicológica. Desconfiá de quien prometa curas.
      </p>
    </main>
  );
}
