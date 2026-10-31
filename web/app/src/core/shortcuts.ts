// The things a single key does in a project, as in the Mac app. Keys are stored by name: `space`, an
// arrow (`left`, `right`, `up`, `down`), or one lowercase character.

export type ShortcutAction = "playPause" | "back" | "forward" | "previousLine" | "nextLine" | "slower" | "faster" | "markSection";

export const actions: { id: ShortcutAction; title: string; defaults: string[] }[] = [
  { id: "playPause", title: "Play or pause", defaults: ["space", "k"] },
  { id: "back", title: "Back 5 seconds", defaults: ["left", "j"] },
  { id: "forward", title: "Forward 5 seconds", defaults: ["right", "l"] },
  { id: "previousLine", title: "Previous line", defaults: ["up"] },
  { id: "nextLine", title: "Next line", defaults: ["down"] },
  { id: "slower", title: "Play slower", defaults: ["["] },
  { id: "faster", title: "Play faster", defaults: ["]"] },
  { id: "markSection", title: "Mark section", defaults: ["m"] },
];

const names: Record<string, string> = { space: "Space", left: "←", right: "→", up: "↑", down: "↓" };

/** `?` opens the list of shortcuts, so it can't be given to anything else. */
export const reserved = new Set(["?"]);

/** A key name from a KeyboardEvent, or null for keys that can't be shortcuts. */
export function keyName(event: KeyboardEvent): string | null {
  const arrows: Record<string, string> = { " ": "space", ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" };
  if (arrows[event.key]) return arrows[event.key];
  return validKey(event.key);
}

export function validKey(raw: string): string | null {
  if (names[raw]) return raw;
  if ([...raw].length !== 1 || /\s|\p{Cc}/u.test(raw)) return null;
  return raw.toLowerCase();
}

/** How a key reads on a key cap: "Space", "←", "M". */
export const symbol = (key: string) => names[key] ?? key.toUpperCase();

export type AddResult = { kind: "added" } | { kind: "moved"; from: ShortcutAction } | { kind: "reserved" };

/** Which keys do what. Only actions whose keys differ from the defaults are stored. */
export class ShortcutMap {
  private keys = new Map<ShortcutAction, string[]>();

  constructor(stored: Record<string, string[] | string> = {}) {
    for (const a of actions) this.keys.set(a.id, [...a.defaults]);
    for (const a of actions) {
      const raw = stored[a.id];
      if (raw == null) continue;
      this.keys.set(a.id, []);
      for (const k of (Array.isArray(raw) ? raw : [raw]).map(validKey)) if (k) this.add(k, a.id);
    }
  }

  get stored(): Record<string, string[]> {
    const out: Record<string, string[]> = {};
    for (const a of actions) {
      const keys = this.keysFor(a.id);
      if (keys.join() !== a.defaults.join()) out[a.id] = keys;
    }
    return out;
  }

  keysFor(action: ShortcutAction): string[] {
    return this.keys.get(action) ?? [];
  }

  action(key: string): ShortcutAction | undefined {
    return actions.find((a) => this.keysFor(a.id).includes(key))?.id;
  }

  /** Gives `key` to `action` as one more key, taking it from whatever had it. */
  add(key: string, action: ShortcutAction): AddResult {
    if (reserved.has(key)) return { kind: "reserved" };
    const previous = this.action(key);
    if (previous === action) return { kind: "added" };
    if (previous) this.keys.set(previous, this.keysFor(previous).filter((k) => k !== key));
    this.keys.set(action, [...this.keysFor(action), key]);
    return previous ? { kind: "moved", from: previous } : { kind: "added" };
  }

  remove(key: string, action: ShortcutAction) {
    this.keys.set(action, this.keysFor(action).filter((k) => k !== key));
  }
}
