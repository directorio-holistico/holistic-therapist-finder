"use client";

import { useSyncExternalStore } from "react";
import { parseTheme, THEME_STORAGE_KEY, type Theme } from "@/lib/theme";

const listeners = new Set<() => void>();

function subscribe(callback: () => void) {
  listeners.add(callback);
  return () => {
    listeners.delete(callback);
  };
}

function getSnapshot(): Theme {
  return parseTheme(document.documentElement.getAttribute("data-theme"));
}

function getServerSnapshot(): Theme {
  return "claro";
}

function choose(next: Theme) {
  document.documentElement.setAttribute("data-theme", next);
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, next);
  } catch {
    // Storage blocked: the choice lasts only for this visit. / Almacenamiento bloqueado: la elección dura solo esta visita.
  }
  listeners.forEach((listener) => listener());
}

export function ThemeToggle() {
  const theme = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const isDark = theme === "oscuro";
  return (
    <button
      type="button"
      onClick={() => choose(isDark ? "claro" : "oscuro")}
      className="inline-flex min-h-11 items-center gap-2 rounded-full border border-linea px-4 text-sm font-medium text-tinta hover:bg-superficie focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento"
    >
      <span aria-hidden="true">{isDark ? "☀" : "☾"}</span>
      {isDark ? "Modo claro" : "Modo oscuro"}
    </button>
  );
}
