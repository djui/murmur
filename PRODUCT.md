# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

The Murmur app is a native macOS SwiftUI app (macOS 26 or later, Apple silicon only) and follows Apple's macOS conventions. The landing page in `site/` (published at https://djui.github.io/murmur/) is a separate `web` surface.

## Users

- **People who record calls.** Knowledge workers recording their own meetings and calls (typically 10–120 minutes, 3–5 speakers) who need a transcript with speakers and the moments they marked during the call.
- **Interviewers and podcasters.** Journalists, researchers and podcasters who pull quotes and cut audio or video clips from interviews and depend on exact word timing.
- **Privacy-bound professionals.** People who cannot upload audio at all (legal, medical, HR, protected sources), for whom on-device processing is a requirement, not a perk.

## Product Purpose

Murmur transcribes audio and video on the Mac and shows who spoke when on a timeline. Drop in an interview, a podcast or a call, or record one live; Murmur writes down every word, tells the voices apart and lays them out on a timeline you can play, mark and cut. Success is a correct, speaker-attributed transcript you can trust enough to quote, clip and export, without the recording ever leaving the Mac.

## Positioning

- **Nothing leaves the Mac.** No account, no upload, no subscription. The only network traffic is the one-time model download and an anonymous usage count Desert Ant Labs receives when a model loads; audio is never sent.
- **Speakers on a timeline.** Every word has a time and a voice, laid out as a speaker-coloured waveform with one lane per speaker, not a text dump.
- **Fast, small models.** Six small specialised models run one after another instead of one big cloud model: about 10 s for 10 minutes of audio on an M2 (Release build).
- **Free and open source.** Free to download, source on GitHub, buildable with `make run`.

## Operating Context

- **Import:** AVFoundation-native files (mp3, m4a, aac, wav, aiff, flac, caf, mp4, m4v, mov). No WebM.
- **Recording:** a compact floating window records the microphone ("Me") and other apps' sound ("Others") as two tracks with a live transcript. It is hidden from screen sharing by default, can shrink to a strip, and ⌥⌘M marks a moment from any app. Speakers are separated when recording stops and the result opens as a project.
- **Projects:** `.murmur` packages anywhere in Finder plus a library window of past projects. Projects reference the original media (security-scoped bookmark) rather than copying it.
- **Work in the project window:** play, zoom and scrub the timeline; mark sections with M; fix words, rename, merge and reassign speakers; copy or export.
- **Keyboard:** Space plays or pauses, ← → jumps five seconds, M starts or ends a mark, Esc cancels.

## Capabilities and Constraints

- **Pipeline models and their names** (user-facing terminology): Ear (spoken language), Voz (words, based on NVIDIA Parakeet TDT 0.6B v3), Who (speakers), Align (word timing, re-times edited words), Tongue (checks text language), Uhm (um/uh fillers, hidden in exports by default), Clear (audio enhancement for playback, transcription and export). Apple Intelligence names projects and writes summaries where available. Apple's on-device transcriber handles languages Voz lacks.
- **Marks:** multiple named marks, snapped to word boundaries; copy or export one or all.
- **Redaction:** one toggle hides names, phone numbers, emails, addresses and IDs in the transcript, copies and exports; exported audio clips are bleeped. Any single detail can be shown again from the sidebar.
- **Export:** plain text, text with timestamps, Markdown, SRT, WebVTT, word-level JSON, and audio or video clips (one per mark, or joined).
- **Editing:** everything is undoable.
- **Speaker colour schemes:** Vivid, Ink, Carbon, Tableau, Slate, Calm, Color-blind safe (Okabe–Ito), High contrast and Earth, each in light and dark.
- **Requirements:** macOS 26+, Apple silicon only (the Desert Ant SDK does not build for Intel). App is about 4 MB; speech models (about 515 MB) download once on first launch; Uhm and Clear download when turned on.
- **Distribution:** Developer ID signed, notarized, Sparkle auto-update, DMGs on GitHub Releases (`djui/murmur`).
- **Headless mode:** the app binary runs the pipeline without UI for testing.
- **Not supported by design:** cross-file voice memory.

## Brand Commitments

- Name: **Murmur**. Tagline in use: "Who said what, when."
- Model names (Voz, Who, Ear, Align, Tongue, Uhm, Clear) are product vocabulary and appear in the UI and copy.
- App appearance follows the system: light and dark, **system accent colour, no custom accent** (decision recorded in `PLAN.md`).
- Voice, as observed in the shipped copy: plain, concrete and specific; short sentences; real numbers instead of superlatives; no hype.
- Credits: Voz weights CC BY 4.0 (attribution required); Desert Ant Labs models under the Desert Ant Labs Source-Available License. Updates by Sparkle.
- Author: Uwe Dauernheim.

## Evidence on Hand

- App screenshots in light and dark: `site/assets/screenshot-*.png`, `site/assets/img/hero-*`, `recorder-*`, `strip-*`, and `docs/screenshots/`.
- `site/assets/sample.m4a`: forty seconds with synthetic voices (Maya, Jonas, Producer), transcribed by Murmur, used in the site's interactive timeline.
- Benchmark: ten minutes of audio on an M2, Release build: decode 0.6 s, language 1.5 s, Voz 1.7 s, Who 1.6 s, Align 1.5 s, Uhm 3 s.
- Changelog via GitHub Releases.
- **Absent, do not fabricate:** testimonials, user or download counts, press, customer logos, accuracy (WER) figures, comparisons against named competitors.

## Product Principles

1. **On-device is non-negotiable.** No feature may send audio, transcripts or project data off the Mac.
2. **Time and voice are the spine.** Every word stays tied to its moment and its speaker; edits, marks, cuts and exports preserve that link.
3. **Trustworthy enough to quote.** Precision (word-snapped cuts, re-timed edits, clear redaction) matters more than feature count.
4. **Native and quiet.** Behave like a well-made Mac app: system conventions, keyboard first, the content in front.
5. **Say real things.** Copy and claims use measured numbers and concrete behaviour, never invented proof.

## Accessibility & Inclusion

- Every speaker colour scheme is tested for contrast (≥3:1) and for speakers that stay distinct (OKLab distance), in light and dark; a colour-blind safe (Okabe–Ito) and a high-contrast scheme ship.
- Speaker identity must never rely on colour alone where a lane, name or label can carry it.
- Controls carry VoiceOver labels (timeline, playhead value, zoom, speaker names); new UI keeps that standard.
