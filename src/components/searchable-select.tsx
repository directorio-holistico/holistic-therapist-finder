"use client";

// A select you can type in. Empty text shows every option; from 3 letters it filters (see option-filter). The value travels in a
// hidden input with the same name as the old <select>, so forms and server code do not change. Before JavaScript loads it is a
// plain <select>, so the search form still works without JavaScript.
// Un select donde se puede escribir. Sin texto muestra todo; desde 3 letras filtra (ver option-filter). El valor viaja en un input
// oculto con el mismo nombre del <select> anterior, así los formularios y el código del servidor no cambian. Antes de que cargue
// JavaScript es un <select> común, así que el buscador sigue funcionando sin JavaScript.

import { useEffect, useId, useRef, useState, useSyncExternalStore, type ChangeEvent, type KeyboardEvent } from "react";
import type { CatalogOption } from "@/lib/catalogs";
import { filterOptions, isFiltering } from "@/lib/option-filter";

const STYLES = {
  site: {
    field: "min-h-11 w-full rounded-xl border border-campo bg-superficie py-2 pl-3 pr-9 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento",
    native: "min-h-11 w-full rounded-xl border border-campo bg-superficie px-3 py-2 text-base text-tinta focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-acento",
    list: "rounded-xl border border-campo bg-superficie text-tinta shadow-md",
    active: "bg-boton text-boton-texto",
    chevron: "text-apagado",
  },
  plain: {
    field: "w-full rounded-md border border-zinc-400 bg-white p-3 pr-9 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100",
    native: "w-full rounded-md border border-zinc-400 bg-white p-3 text-zinc-900 dark:bg-zinc-900 dark:text-zinc-100",
    list: "rounded-md border border-zinc-400 bg-white text-zinc-900 shadow-md dark:bg-zinc-900 dark:text-zinc-100",
    active: "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900",
    chevron: "text-zinc-600 dark:text-zinc-400",
  },
} as const;

type Props = {
  id: string;
  name: string;
  options: readonly CatalogOption[];
  // Text of the "no choice" row ("Todas las terapias", "Ninguna"...). / Texto de la fila "sin elección".
  emptyLabel: string;
  listLabel: string;
  // Selected id as text, "" for none. / Id elegido como texto, "" si no hay.
  defaultValue: string;
  variant: keyof typeof STYLES;
  invalid?: boolean;
  // Called only when the person picks a different value (typing a filter does not call it). / Solo cuando la persona elige otro valor.
  onSelect?: (value: string) => void;
};

const subscribe = () => () => {};

export function SearchableSelect(props: Props) {
  // false while the server renders and while the page hydrates, true after: the native select is swapped for the combo box.
  // falso mientras el servidor renderiza y la página se hidrata, verdadero después: el select nativo se cambia por el combo.
  const ready = useSyncExternalStore(subscribe, () => true, () => false);
  return ready ? <Combobox {...props} /> : <NativeSelect {...props} />;
}

function NativeSelect({ id, name, options, emptyLabel, defaultValue, variant, invalid }: Props) {
  return (
    <select id={id} name={name} defaultValue={defaultValue} aria-invalid={invalid} className={STYLES[variant].native}>
      <option value="">{emptyLabel}</option>
      {options.map((option) => (
        <option key={option.id} value={option.id}>{option.name}</option>
      ))}
    </select>
  );
}

function Combobox({ id, name, options, emptyLabel, listLabel, defaultValue, variant, invalid, onSelect }: Props) {
  const style = STYLES[variant];
  const listId = useId();
  const labelOf = (value: string) => (value === "" ? emptyLabel : (options.find((option) => String(option.id) === value)?.name ?? ""));
  const [value, setValue] = useState(defaultValue);
  const [text, setText] = useState(() => labelOf(defaultValue));
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const listRef = useRef<HTMLUListElement>(null);

  const filtering = isFiltering(query);
  const rows = [
    ...(filtering ? [] : [{ value: "", name: emptyLabel }]),
    ...filterOptions(options, query).map((option) => ({ value: String(option.id), name: option.name })),
  ];
  const expanded = open && rows.length > 0;
  const status = !open || !filtering ? "" : rows.length === 0 ? "Sin coincidencias." : `${rows.length} ${rows.length === 1 ? "coincidencia" : "coincidencias"}.`;

  useEffect(() => {
    if (!open) return;
    listRef.current?.querySelector<HTMLElement>('[data-active="true"]')?.scrollIntoView({ block: "nearest" });
  }, [open, active]);

  // Opens the full list with the current choice highlighted (row 0 is the "no choice" row). / Abre la lista completa con la elección actual resaltada.
  function openList() {
    setQuery("");
    setOpen(true);
    setActive(value === "" ? 0 : options.findIndex((option) => String(option.id) === value) + 1);
  }

  function choose(next: string) {
    setText(labelOf(next));
    setQuery("");
    setOpen(false);
    setActive(-1);
    if (next !== value) {
      setValue(next);
      onSelect?.(next);
    }
  }

  function onType(event: ChangeEvent<HTMLInputElement>) {
    // Typing a filter is not a change of the form: the parent form must not see it. / Escribir un filtro no es un cambio del formulario.
    event.stopPropagation();
    const next = event.target.value;
    setText(next);
    setQuery(next);
    setOpen(true);
    setActive(isFiltering(next) ? 0 : -1);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (!open) openList();
        else setActive((current) => Math.min(rows.length - 1, current + 1));
        break;
      case "ArrowUp":
        event.preventDefault();
        if (!open) openList();
        else setActive((current) => Math.max(0, current - 1));
        break;
      case "Enter": {
        // Enter picks the highlighted row; it never submits the form from here. / Enter elige la fila resaltada; nunca envía el formulario desde acá.
        event.preventDefault();
        const row = rows[active];
        if (open && row) choose(row.value);
        break;
      }
      case "Escape":
        if (open) {
          event.preventDefault();
          setOpen(false);
          setQuery("");
          setText(labelOf(value));
        }
        break;
    }
  }

  // Leaving the box: empty text means "no choice"; any other text goes back to the chosen option's name.
  // Al salir de la caja: texto vacío significa "sin elección"; cualquier otro texto vuelve al nombre de la opción elegida.
  function onBlur() {
    setOpen(false);
    setQuery("");
    if (text.trim() === "") choose("");
    else setText(labelOf(value));
  }

  return (
    <div className="relative">
      <input
        id={id}
        type="text"
        role="combobox"
        aria-expanded={expanded}
        aria-controls={expanded ? listId : undefined}
        aria-autocomplete="list"
        aria-activedescendant={expanded && rows[active] ? `${listId}-${active}` : undefined}
        aria-invalid={invalid}
        autoComplete="nope"
        autoCapitalize="none"
        autoCorrect="off"
        spellCheck={false}
        value={text}
        onChange={onType}
        onKeyDown={onKeyDown}
        onFocus={(event) => { event.target.select(); openList(); }}
        onClick={() => { if (!open) openList(); }}
        onBlur={onBlur}
        className={style.field}
      />
      <span aria-hidden="true" className={`pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm ${style.chevron}`}>▾</span>
      <input type="hidden" name={name} value={value} />
      <p role="status" className="sr-only">{status}</p>
      {expanded && (
        <ul ref={listRef} id={listId} role="listbox" aria-label={listLabel} className={`absolute z-20 mt-1 max-h-64 w-full overflow-y-auto ${style.list}`}>
          {rows.map((row, index) => (
            <li
              key={row.value === "" ? "none" : row.value}
              id={`${listId}-${index}`}
              role="option"
              aria-selected={row.value === value}
              data-active={index === active}
              // Keeps the focus in the text box so the click is not lost to a blur. / Deja el foco en la caja para que el clic no se pierda por un blur.
              onMouseDown={(event) => event.preventDefault()}
              onMouseMove={() => { if (active !== index) setActive(index); }}
              onClick={() => choose(row.value)}
              className={`cursor-pointer px-3 py-2 ${index === active ? style.active : ""} ${row.value === value ? "font-semibold" : ""}`}
            >
              {row.name}
            </li>
          ))}
        </ul>
      )}
      {open && filtering && rows.length === 0 && (
        <div className={`absolute z-20 mt-1 w-full px-3 py-2 text-sm ${style.list}`}>Sin coincidencias. Borrá letras para ver todas las opciones.</div>
      )}
    </div>
  );
}
