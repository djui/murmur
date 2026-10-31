// Messages between the page and the model workers. Every request carries an id; the worker answers
// with progress for that id and then a result or an error.
import type { RedactedSpan, Word } from "../core/project";
import type { SpeakerTurn } from "../core/merge";

export interface Runtimes {
  /** Absolute URLs of the runtime folders this site serves. */
  ort: string;
  litert: string;
}

export type VozRequest =
  | { op: "load"; runtimes: Runtimes }
  | { op: "transcribe"; runtimes: Runtimes; file: Blob | Float32Array };

export type LiteRtRequest =
  | { op: "ear"; runtimes: Runtimes; samples: Float32Array }
  | { op: "who"; runtimes: Runtimes; samples: Float32Array }
  | { op: "redact"; runtimes: Runtimes; words: Word[] }
  | { op: "clear"; runtimes: Runtimes; samples: Float32Array };

export interface LanguageDetection {
  language: string | null;
  confidence: number;
  isReliable: boolean;
}

export interface Results {
  load: true;
  transcribe: { words: { text: string; start: number; end: number }[]; duration: number };
  ear: LanguageDetection;
  who: SpeakerTurn[];
  redact: RedactedSpan[];
  clear: Float32Array;
}

export type Envelope<T> = { id: number } & T;

export type Reply =
  | { id: number; kind: "progress"; phase: "download" | "run"; fraction: number }
  | { id: number; kind: "done"; result: unknown }
  | { id: number; kind: "failed"; message: string };
