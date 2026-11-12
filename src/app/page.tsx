import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";

export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16 text-center">
      <h1 className="text-3xl font-semibold tracking-tight">{SITE_NAME}</h1>
      <p className="max-w-md text-lg text-zinc-600 dark:text-zinc-400">{SITE_SLOGAN}</p>
      <p className="text-sm text-zinc-500 dark:text-zinc-500">Sitio en construcción.</p>
    </main>
  );
}
