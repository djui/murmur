// Small DOM helpers: element builder, icons, menus, dialogs and toasts.

type Child = Node | string | number | false | null | undefined;
type Attrs = Record<string, unknown> & { class?: string; on?: Record<string, (e: any) => void> };

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Attrs = {}, ...children: (Child | Child[])[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "on") for (const [ev, f] of Object.entries(v as Record<string, (e: Event) => void>)) el.addEventListener(ev, f);
    else if (k === "class") el.className = String(v);
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else if (k === "dataset") Object.assign(el.dataset, v);
    else if (v === true) el.setAttribute(k, "");
    else if (v === false || v == null) continue;
    else if (k in el && typeof v !== "string") (el as unknown as Record<string, unknown>)[k] = v;
    else el.setAttribute(k, String(v));
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : String(c));
  return el;
}

const paths: Record<string, string> = {
  play: "M5 3.5v9l8-4.5z",
  pause: "M4.5 3h2.5v10H4.5zM9 3h2.5v10H9z",
  back: "M8 4 3 8l5 4zM14 4 9 8l5 4z",
  forward: "M8 4l5 4-5 4zM2 4l5 4-5 4z",
  plus: "M7.25 3h1.5v4.25H13v1.5H8.75V13h-1.5V8.75H3v-1.5h4.25z",
  minus: "M3 7.25h10v1.5H3z",
  copy: "M5 2h7a1 1 0 0 1 1 1v8h-1.5V3.5H5zM3 5h6.5a1 1 0 0 1 1 1v7.5a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zm.5 1.5v6.5H9V6.5z",
  export: "M7.25 2h1.5v7.2l2.4-2.4 1.06 1.06L8 12.06 3.8 7.86 4.86 6.8l2.4 2.4zM2 13h12v1.5H2z",
  gear: "M8 5.2a2.8 2.8 0 1 0 0 5.6 2.8 2.8 0 0 0 0-5.6zM6.9 1h2.2l.4 1.9 1.2.6 1.7-1 1.5 1.5-1 1.7.6 1.2 1.9.4v2.2l-1.9.4-.6 1.2 1 1.7-1.5 1.5-1.7-1-1.2.6-.4 1.9H6.9l-.4-1.9-1.2-.6-1.7 1-1.5-1.5 1-1.7-.6-1.2L1 9.1V6.9l1.9-.4.6-1.2-1-1.7 1.5-1.5 1.7 1 1.2-.6z",
  sidebar: "M2 3h12v10H2zm1.5 1.5v7h6v-7zm7.5 0v7h1.5v-7z",
  mark: "M4 2h8v12l-4-3-4 3z",
  trash: "M6 2h4l.5 1H13v1.5H3V3h2.5zM4 6h8l-.6 8H4.6z",
  close: "M4 3l4 4 4-4 1 1-4 4 4 4-1 1-4-4-4 4-1-1 4-4-4-4z",
  file: "M4 1.5h5.5L13 5v9.5H4zm5 1V6h3.5z",
  undo: "M5 4V1L1 5l4 4V6h4a3 3 0 0 1 0 6H6v1.5h3A4.5 4.5 0 0 0 9 4.5z",
  edit: "M11 2l3 3-8 8H3v-3zm-1.5 2.5L4.5 9.5V11.5h2L11.5 6.5z",
  keyboard: "M1.5 4h13v8h-13zM3 5.5v1h1.5v-1zm2.5 0v1H7v-1zM8 5.5v1h1.5v-1zm2.5 0v1H12v-1zM3 8v1h1.5V8zm2.5 0v1h5V8zM11.5 8v1H13V8zM4.5 10.5v1h7v-1z",
  wand: "M2 13 11 4l1 1-9 9zM12 1l.5 1.5L14 3l-1.5.5L12 5l-.5-1.5L10 3l1.5-.5zM5 2l.4 1L6.5 3.5l-1.1.4L5 5l-.4-1.1L3.5 3.5l1.1-.5z",
  eye: "M8 3.5C4.5 3.5 2 6.5 1 8c1 1.5 3.5 4.5 7 4.5S14 9.5 15 8c-1-1.5-3.5-4.5-7-4.5zM8 5.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z",
};

export function icon(name: keyof typeof paths | string, label?: string): SVGSVGElement {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 16 16");
  svg.setAttribute("class", "icon-svg");
  svg.setAttribute("fill", "currentColor");
  if (label) svg.setAttribute("aria-label", label);
  else svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("d", paths[name] ?? "");
  path.setAttribute("fill-rule", "evenodd");
  svg.append(path);
  return svg;
}

export function button(label: string, onClick: (e: MouseEvent) => void, opts: { icon?: string; title?: string; class?: string; iconOnly?: boolean } = {}): HTMLButtonElement {
  return h("button", {
    type: "button",
    class: `btn ${opts.iconOnly ? "icon" : ""} ${opts.class ?? ""}`,
    title: opts.title ?? (opts.iconOnly ? label : undefined),
    "aria-label": opts.iconOnly ? label : undefined,
    on: { click: onClick },
  }, opts.icon ? icon(opts.icon) : null, opts.iconOnly ? null : label);
}

export interface MenuItem {
  label: string;
  action?: () => void;
  separator?: boolean;
  heading?: boolean;
  checked?: boolean;
}

let openMenu: HTMLElement | undefined;

export function closeMenu() {
  openMenu?.remove();
  openMenu = undefined;
}

/** A small menu at a point or under an element; Escape or a click elsewhere closes it. */
export function menu(items: MenuItem[], at: HTMLElement | { x: number; y: number }) {
  closeMenu();
  const el = h("div", { class: "menu", role: "menu" }, items.map((item) =>
    item.separator ? h("hr") : item.heading ? h("div", { class: "label" }, item.label)
      : h("button", { role: "menuitem", on: { click: () => { closeMenu(); item.action?.(); } } }, item.checked == null ? "" : item.checked ? "✓" : " ", item.label),
  ));
  document.body.append(el);
  const r = at instanceof HTMLElement ? at.getBoundingClientRect() : { left: at.x, bottom: at.y, top: at.y };
  const w = el.offsetWidth, hgt = el.offsetHeight;
  el.style.left = `${Math.max(8, Math.min(innerWidth - w - 8, r.left))}px`;
  el.style.top = `${r.bottom + hgt + 8 > innerHeight ? Math.max(8, r.top - hgt - 4) : r.bottom + 4}px`;
  openMenu = el;
  (el.querySelector("button") as HTMLButtonElement | null)?.focus();
  el.addEventListener("keydown", (e) => {
    const buttons = [...el.querySelectorAll("button")];
    const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === "ArrowDown") { buttons[(i + 1) % buttons.length]?.focus(); e.preventDefault(); }
    if (e.key === "ArrowUp") { buttons[(i - 1 + buttons.length) % buttons.length]?.focus(); e.preventDefault(); }
  });
}

addEventListener("mousedown", (e) => {
  if (openMenu && !openMenu.contains(e.target as Node)) closeMenu();
});
addEventListener("keydown", (e: KeyboardEvent) => {
  if (e.key === "Escape") closeMenu();
});

/** A modal dialog. Resolves with the value its buttons pass to `done`, or undefined when dismissed. */
export function dialog<T>(title: string, build: (done: (value?: T) => void) => { body: Child[]; foot: Child[] }): Promise<T | undefined> {
  return new Promise((resolve) => {
    const d = h("dialog", { "aria-label": title });
    let value: T | undefined;
    const done = (v?: T) => {
      value = v;
      d.close();
    };
    const { body, foot } = build(done);
    d.append(h("div", { class: "head" }, title), h("div", { class: "body" }, body), h("div", { class: "foot" }, foot));
    d.addEventListener("close", () => {
      d.remove();
      resolve(value);
    });
    document.body.append(d);
    d.showModal();
  });
}

export function confirm(title: string, message: string, action: string, danger = false): Promise<boolean> {
  return dialog<boolean>(title, (done) => ({
    body: [h("p", { style: { margin: "0" } }, message)],
    foot: [button("Cancel", () => done(false)), button(action, () => done(true), { class: danger ? "danger" : "primary" })],
  })).then(Boolean);
}

let toastTimer: number | undefined;

export function toast(message: string) {
  document.querySelector(".toast")?.remove();
  const el = h("div", { class: "toast", role: "status" }, message);
  document.body.append(el);
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => el.remove(), 2400);
}

export function download(blob: Blob, name: string) {
  const a = h("a", { href: URL.createObjectURL(blob), download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
}

export const megabytes = (bytes: number) => (bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.round(bytes / 1e6)} MB`);
