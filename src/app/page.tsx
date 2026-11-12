import Link from "next/link";
import { SITE_NAME, SITE_SLOGAN } from "@/lib/site";

export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16 text-center">
      <h1 className="text-3xl font-semibold tracking-tight">{SITE_NAME}</h1>
      <p className="max-w-md text-lg text-zinc-600 dark:text-zinc-400">{SITE_SLOGAN}</p>
      <Link
        href="/buscar"
        className="rounded-md bg-zinc-900 px-5 py-2 text-base font-medium text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
      >
        Buscar terapeuta
      </Link>
      <p className="text-sm text-zinc-500 dark:text-zinc-500">Sitio en construcción.</p>
    </main>
  );
}
