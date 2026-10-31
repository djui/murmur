// Preferences, kept in this browser (localStorage). Reading never fails: a private window or blocked
// storage just means the defaults.
import type { SchemeId } from "./core/palettes";
import type { RedactionStyle } from "./core/redactor";
import { ShortcutMap } from "./core/shortcuts";
import type { TextFormat } from "./core/formats";

export interface Settings {
  scheme: SchemeId;
  appearance: "system" | "light" | "dark";
  shortcuts: Record<string, string[]>;
  redactionStyle: RedactionStyle;
  copyFormat: TextFormat;
  hideFillers: boolean;
  speakerNames: boolean;
  verticalTimeline: boolean;
  inspector: boolean;
}

const defaults: Settings = {
  scheme: "vivid",
  appearance: "system",
  shortcuts: {},
  redactionStyle: "labels",
  copyFormat: "plain",
  hideFillers: true,
  speakerNames: true,
  verticalTimeline: false,
  inspector: true,
};

const KEY = "murmur.settings";
let current: Settings = load();
const listeners = new Set<() => void>();

function load(): Settings {
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem(KEY) ?? "{}") };
  } catch {
    return { ...defaults };
  }
}

export const settings = (): Settings => current;

export function update(change: Partial<Settings>) {
  current = { ...current, ...change };
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
  } catch {
    // Not saved; the change still holds for this visit.
  }
  applyAppearance();
  for (const f of listeners) f();
}

export function onChange(f: () => void): () => void {
  listeners.add(f);
  return () => listeners.delete(f);
}

export const shortcutMap = () => new ShortcutMap(current.shortcuts);

const darkQuery = matchMedia("(prefers-color-scheme: dark)");
export const isDark = () => current.appearance === "dark" || (current.appearance === "system" && darkQuery.matches);

export function applyAppearance() {
  if (current.appearance === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.dataset.theme = current.appearance;
}

darkQuery.addEventListener("change", () => {
  for (const f of listeners) f();
});
