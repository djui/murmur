// Settings: appearance, speaker colors, redaction style, keyboard shortcuts and the models on disk.
import { colors, schemes, type SchemeId } from "../core/palettes";
import { redactionStyles, type RedactionStyle } from "../core/redactor";
import { actions, keyName, symbol, type ShortcutAction } from "../core/shortcuts";
import { models, persist, remove, sizes } from "../models";
import { isDark, settings, shortcutMap, update } from "../settings";
import { button, confirm, dialog, h, megabytes, toast } from "./dom";

function swatches(id: SchemeId) {
  return h("span", { style: { display: "inline-flex", gap: "3px", marginLeft: "8px", verticalAlign: "middle" } },
    colors(id).slice(0, 5).map((c) => h("span", { style: { width: "10px", height: "10px", borderRadius: "3px", background: `#${c[isDark() ? 1 : 0]}` } })));
}

function shortcutRows(container: HTMLElement) {
  const map = shortcutMap();
  container.replaceChildren(...actions.map((a) =>
    h("div", { class: "shortcut-row" },
      h("span", {}, a.title),
      h("span", {}, map.keysFor(a.id).map((k) => h("button", {
        class: "keycap", title: `Remove ${symbol(k)}`, style: { marginRight: "4px", cursor: "pointer" },
        on: { click: () => { map.remove(k, a.id); update({ shortcuts: map.stored }); shortcutRows(container); } },
      }, symbol(k)))),
      button("Add key", () => recordKey(a.id, container)),
    )),
    h("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "center" } },
      h("span", { class: "note" }, "Click a key to remove it. Press ? in a project to see them all."),
      button("Restore defaults", () => { update({ shortcuts: {} }); shortcutRows(container); })),
  );
}

function recordKey(action: ShortcutAction, container: HTMLElement) {
  toast("Press a key…");
  const onKey = (e: KeyboardEvent) => {
    e.preventDefault();
    e.stopPropagation();
    removeEventListener("keydown", onKey, true);
    if (e.key === "Escape") return;
    const key = keyName(e);
    if (!key || e.metaKey || e.ctrlKey || e.altKey) return toast("Use a single key without ⌘, ⌥ or ⌃.");
    const map = shortcutMap();
    const result = map.add(key, action);
    if (result.kind === "reserved") return toast(`${symbol(key)} shows the shortcuts and can't be changed.`);
    if (result.kind === "moved") toast(`${symbol(key)} no longer does “${actions.find((a) => a.id === result.from)!.title}”.`);
    update({ shortcuts: map.stored });
    shortcutRows(container);
  };
  addEventListener("keydown", onKey, true);
}

async function modelRows(container: HTMLElement) {
  const bytes = await sizes();
  const persisted = (await navigator.storage?.persisted?.().catch(() => false)) ?? false;
  const estimate = await navigator.storage?.estimate?.().catch(() => undefined);
  container.replaceChildren(
    ...models.map((m) => h("div", { class: "model" },
      h("div", {}, h("div", {}, `${m.title} `, h("span", { class: "tertiary" }, m.engine)), h("div", { class: "note" }, m.detail)),
      h("span", { class: "mono secondary" }, bytes[m.id] ? megabytes(bytes[m.id]) : "Not downloaded"),
      bytes[m.id] ? button("Remove", async () => {
        if (await confirm(`Remove ${m.engine}?`, `${m.engine} downloads again the next time it's needed.`, "Remove")) {
          await remove(m.id);
          modelRows(container);
        }
      }) : h("span"),
    )),
    h("p", { class: "note", style: { margin: "4px 0 0" } },
      `Models stay in this browser${estimate?.quota ? ` (${megabytes(estimate.usage ?? 0)} used of ${megabytes(estimate.quota)} allowed)` : ""}. `,
      persisted ? "The browser keeps them even when the disk fills up." : "The browser may clear them when the disk fills up. ",
      persisted ? null : h("button", { class: "btn", style: { marginTop: "6px" }, on: { click: async () => {
        toast((await persist()) ? "The browser will keep the models." : "The browser didn't agree to keep them; it decides by how often you use the page.");
        modelRows(container);
      } } }, "Ask to keep them")),
  );
}

export function showSettings() {
  const s = settings();
  const shortcuts = h("div", { class: "models" });
  const modelList = h("div", { class: "models" }, h("span", { class: "note" }, "Measuring…"));
  shortcutRows(shortcuts);
  modelRows(modelList);
  const select = <T extends string>(value: T, options: { id: T; title: string }[], onChange: (v: T) => void, label: string) =>
    h("select", { "aria-label": label, on: { change: (e: Event) => onChange((e.target as HTMLSelectElement).value as T) } },
      options.map((o) => h("option", { value: o.id, selected: o.id === value }, o.title)));

  const schemeNote = h("div", { class: "note" }, schemes.find((x) => x.id === s.scheme)!.note, swatches(s.scheme));
  return dialog("Settings", (done) => ({
    body: [
      h("div", { class: "grid2" },
        h("label", {}, "Appearance"),
        select(s.appearance, [{ id: "system", title: "System" }, { id: "light", title: "Light" }, { id: "dark", title: "Dark" }], (appearance) => update({ appearance }), "Appearance"),
        h("label", {}, "Speaker colors"),
        h("div", {}, select(s.scheme, schemes, (scheme) => {
          update({ scheme });
          schemeNote.replaceChildren(schemes.find((x) => x.id === scheme)!.note, swatches(scheme));
        }, "Speaker colors"), schemeNote),
        h("label", {}, "Hidden details read"),
        select<RedactionStyle>(s.redactionStyle, redactionStyles, (redactionStyle) => update({ redactionStyle }), "Hidden details read"),
      ),
      h("h3", { class: "section-title", style: { margin: "8px 0 0" } }, "Keyboard"),
      shortcuts,
      h("h3", { class: "section-title", style: { margin: "8px 0 0" } }, "Models"),
      modelList,
    ],
    foot: [button("Done", () => done(), { class: "primary" })],
  }));
}

/** The list of shortcuts, from `?`. */
export function showShortcuts() {
  const map = shortcutMap();
  return dialog("Keyboard shortcuts", (done) => ({
    body: [
      ...actions.map((a) => h("div", { class: "shortcut-row" }, h("span", {}, a.title), h("span", {}, map.keysFor(a.id).map((k) => h("span", { class: "keycap", style: { marginRight: "4px" } }, symbol(k)))), h("span"))),
      h("div", { class: "shortcut-row" }, h("span", {}, "Undo / Redo"), h("span", {}, h("span", { class: "keycap" }, "⌘Z"), " ", h("span", { class: "keycap" }, "⇧⌘Z")), h("span")),
      h("div", { class: "shortcut-row" }, h("span", {}, "Cancel a selection or a mark"), h("span", { class: "keycap" }, "Esc"), h("span")),
      h("p", { class: "note" }, "Change them in Settings."),
    ],
    foot: [button("Done", () => done(), { class: "primary" })],
  }));
}
