# Murmur — local transcript + speaker timeline app (plan, v2)

Nothing implemented yet. Mockup (v2, reflects the decisions below):
https://claude.ai/artifact/WSbpwvQV4yFtjADuQSexEY

## 1. Decisions so far

| Topic | Decision |
|---|---|
| Platform | Native macOS app, SwiftUI, **macOS 26+, Apple silicon only** |
| Audience | Personal first; built for distribution: **Developer ID signing, notarization, Sparkle auto-update** |
| Languages | English, German, French, Spanish (all supported by Voz *and* Align) |
| Unsupported language | Ask the user: transcribe anyway with Voz / use Apple's on-device transcriber / pick language manually / cancel |
| Formats | AVFoundation-native only: mp3, m4a, aac, wav, aiff, flac, caf, mp4, m4v, mov. **No WebM** (no FFmpeg) |
| Typical input | Meetings, 10–120 min, 3–5 speakers |
| Speaker fixes | Merge speakers, reassign a paragraph or a word range, split a paragraph (nice-to-have) |
| Cross-file voice memory | No |
| Transcript | **Editable**, with undo; edited words are re-timed with Align |
| Marks | Multiple named marks; cuts snap to **word** boundaries |
| Export | Text, Markdown, SRT, WebVTT, JSON, **plus audio/video clip export** |
| Copy format | User-selectable (Settings default + "Copy as ▸" menu) |
| Persistence | **Projects**, plus a **library** of past projects |
| Video | Toggleable video panel (hidden for audio-only files) |
| Layout | Timeline on top, transcript below (as mockup) |
| Appearance | Light + dark, follows system; **system accent colour**, no custom accent |
| Name | Murmur |
| Models | Download on first launch (Voz + Who); Ear/Align/Tongue bundled |
| Extras | **Uhm** (fillers), **Clear** (audio enhancement), **Title** (title + summary) |
| Live capture | **Microphone and system audio** recording |
| Apple Developer account | Yes → Developer ID + notarization; Sparkle appcast + DMGs on **GitHub Releases** (`djui/murmur`) |
| Project media | **Referenced** (security-scoped bookmark), never copied; "Locate file…" when it moves |
| Project storage | `.murmur` files anywhere in Finder **plus** a library window listing recent projects |
| Recording transcript | **Live** while recording; mic track is labelled **"Me"** by default |
| Recording window | New recordings open in the **compact floating window**; the full recording window is one click away |
| Clip export of several marks | User picks: separate files or one joined file |
| Uhm | "Hide fillers" **on by default** in exports (fillers still visible, faded, in the editor) |
| Clear | Applied to transcription input **and** playback **and** export (toggleable per project) |
| Title | Auto-names new projects (and writes a short summary); user can rename |

## 2. Models and their roles

| Model | Role | Size | Shipping |
|---|---|---|---|
| Voz | Transcript + word timestamps (25 langs, ~250–760× realtime) | 467 MB | First-launch download |
| Who (8-bit) | Speaker turns, overlaps kept | 42 MB | First-launch download |
| Ear | Spoken-language ID before Voz | 5 MB | Bundled |
| Align | Refine word timings; re-time edited words | 0.7 MB | Bundled |
| Tongue | Text language check (Voz output vs Ear) | 2 MB | Bundled |
| Uhm | Mark um/uh/hmm to ~20 ms ("hide fillers") | unknown | On demand (when enabled) |
| Clear | Speech enhancement | unknown | On demand |
| Title | Project title + 1–2 sentence summary | unknown | On demand |
| Apple SpeechTranscriber | Fallback for languages Voz lacks | 0 (system asset) | OS-managed |

Sizes for Uhm/Clear/Title are not published on the product pages; check the Hugging Face
model cards before finalizing the download screen. Licensing: free up to 100k monthly active
devices per model; Voz weights CC BY 4.0 → attribution in About.

## 3. Pipeline (file import)

```
media ─► decode to 16 kHz mono (AVAssetReader) ─► waveform peaks (multi-resolution, cached)
      ├─► Ear → language (+ reliability)
      │      └─ not in Voz's 25 / unreliable → ask user (Voz anyway / Apple transcriber / pick / cancel)
      ├─► [Clear] optional enhancement before transcription
      ├─► Voz → words ┐ parallel
      └─► Who → turns ┘
            └─► Align → refined word times (en/de/fr/es)
                  └─► merge words↔speakers, paragraphs at speaker change / pause > ~1.5 s
                        ├─► [Uhm] filler flags on words
                        ├─► Tongue sanity check → warn if text language ≠ Ear language
                        └─► [Title] project title + summary
```

1-hour meeting on an M1: ~20–25 s total; 2-hour: ~45 s. Who memory peaks ~800 MB at 2 h.

## 4. Live capture (mic + system audio)

- **Mic:** AVAudioEngine input. **System audio:** Core Audio process taps (macOS 14.2+), which
  needs the "System Audio Recording" permission; ScreenCaptureKit audio as the alternative.
- Record mic and system audio as **two separate tracks** in one file. This helps a lot: the mic
  track is (mostly) you, so diarization only has to separate the remote people. The mic track
  becomes speaker **"Me"**; Who runs on the system-audio track only. Echo (your voice leaking
  into system audio, or remote voices into an open mic without headphones) is removed by
  comparing the two tracks before assigning words.
- Live text (decided: yes): Voz is a batch model (15 s windows), so the live transcript runs on
  rolling windows cut at pauses, ~2–5 s behind. "Me" lines are labelled live (mic track); remote
  lines show as "Others" until stop. Who is batch too; it runs once on stop (2 h ≈ 8 s), then
  the final speaker labels and Align timings replace the provisional ones.
- **Compact live window** for meetings: a small floating panel (~340×580, NSPanel) that stays
  on top across Spaces and full-screen apps and is **excluded from screen sharing**
  (`sharingType = .none`). It shows the timer, Me/Others levels, the last few transcript lines,
  Mark (global shortcut ⌥⌘M, works while the call app is focused), Pause and Stop. It shrinks
  to a one-line **strip** (timer, mini waveform, latest line) and the menu bar shows the timer
  while recording. The full recording window is one click away.
- Recordings are written as a `.m4a` with two AAC tracks (mic, system) next to the project;
  the project references it like any imported file.
- Sandboxing: process taps and Sparkle both work outside the Mac App Store. Direct distribution
  (DMG) is assumed.

## 5. Editing model

- Transcript stored as words `{text, start, end, speaker, confidence, isFiller, edited}`.
- Typing replaces a word range; the new words get provisional times spread over the old range,
  then Align re-times them against the audio (milliseconds). Undo/redo via UndoManager.
- Speaker reassignment works on a word range; merge rewrites all words of speaker B → A.
- Marks: `{id, name, start, end, colour}`, start/end snapped to word edges. Shown as a marks
  lane above the waveform and listed in the sidebar (rename, play, copy, export).

## 6. Projects and library

- Document package `.murmur` (folder): `project.json` (words, speakers, names, marks, edits,
  settings), `peaks.bin` (waveform cache); media is **referenced** via a security-scoped
  bookmark plus the last known path and a content hash, so a moved file can be re-found or
  located by hand ("Locate file…").
- `.murmur` files can live anywhere in Finder. The **library window** lists recent projects
  (title from Title or filename, date, duration, speakers), with search, open, reveal in
  Finder, and remove from list. Recording and import start from here too.

## 7. Export

- Text formats: Text, Markdown, SRT, WebVTT, JSON (word-level), options: speaker names,
  timestamps, times relative to the mark, hide fillers (on by default).
- Clip export: AVAssetExportSession (passthrough where possible) for one mark, each mark as a
  separate file, or all marks joined into one file.
- Range: whole file / current selection / one mark / all marks.

## 8. Size and delivery

| Part | Size |
|---|---|
| App (SwiftUI, SDK, Sparkle, bundled Ear + Align + Tongue) | ~25 MB DMG |
| First-launch download: Voz + Who | ≈ 510 MB |
| Optional downloads: Uhm, Clear, Title | TBD |

Sparkle 2 with EdDSA-signed appcast; updates never re-download models (models live in
Application Support). Requires an Apple Developer Program membership for Developer ID +
notarization.

## 9. Build phases

1. App shell: library window, document package, import, decode, waveform, playback, scrubbing,
   video toggle, light/dark.
2. First-launch model download; Voz + Who + merge; transcript view; speaker lanes.
3. Ear gating with the user choice dialog + Apple transcriber fallback; Align; Tongue check.
4. Marks (multiple, named), selection, copy formats, text exports, clip export.
5. Transcript editing + re-timing; speaker rename / merge / reassign / split.
6. Recording: mic + system audio, two tracks, rolling live transcript, process on stop.
7. Extras: Uhm, Clear, Title.
8. Signing, notarization, Sparkle, DMG.

## 10. Risks

- SDK v4 API names come from product pages; verify against the README first.
- Who accuracy on room-mic meetings ~19–21% DER; speaker-fix tools matter.
- Apple SpeechTranscriber fallback quality and language list differ from Voz.
- System-audio capture permission UX on macOS 26 needs a careful onboarding step.
- Editing + re-timing + undo across speaker changes is the most complex part of the UI.

## 11. Implementation status (2026-10-26)

All phases are built; see README.md for build and test commands.

Deviations from the plan, and why:
- **Title/summary** uses Apple Intelligence (Foundation Models) instead of Desert Ant Title: Title needs
  the SDK's `MLX` package trait (XcodeGen can't set it) and a ~280 MB model you populate yourself.
  The step is skipped when Apple Intelligence isn't ready.
- **All Desert Ant models download** (Ear and Align too, not bundled); only Tongue ships in the app.
  First launch fetches ≈ 515 MB into `~/Library/Application Support/com.djui.Murmur/Models`.
- **Language**: Ear first; when it is unsure (< 80 % or flagged unreliable), Voz reads a 90 s sample and
  Tongue names the text's language. Synthetic speech fooled Ear (Hausa 32 %, Estonian 95 % for Japanese).
- **Diarization runs after transcription**, not in parallel: on an M2 running both together made Who
  70× slower (108 s vs 1.6 s for 10 min).
- **arm64 only**: the SDK doesn't compile for x86_64.

Verified: core unit tests (23); headless pipeline on English, German, Japanese (Apple fallback),
a 10-minute file, a two-track recording (Me + 2 others), enhancement, live transcript simulation,
clip export (separate and joined, audio and video), stem mixing; the library, project window,
marks, renaming, playback, export sheet and compact panel in the running app; Release build and DMG.

Not verified: real microphone/system-audio capture (needs the permission prompts), the global ⌥⌘M
hotkey, typing edits through the UI (the retiming logic is unit-tested), title/summary (Apple
Intelligence model not ready on the test Mac), notarization and Sparkle updates (need a Developer ID
certificate, a notary profile and Sparkle keys).
