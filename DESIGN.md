---
name: Murmur
description: Who said what, when. On-device transcripts with every voice on its own lane.
colors:
  accent: "#0a66e0"
  accent-dark: "#2f8cff"
  accent-ink: "#ffffff"
  mark-amber: "#c98a00"
  mark-amber-dark: "#f5b82e"
  mark-ink: "#6e4a00"
  mark-ink-dark: "#f7d17a"
  voice-violet: "#af52de"
  voice-orange: "#ff9500"
  voice-teal: "#30b0c7"
  record-red: "#ff3b30"
  paper: "#f5f4f1"
  surface: "#ffffff"
  well: "#eeede9"
  ink: "#1b1b1d"
  ink-secondary: "#47474d"
  ink-tertiary: "#65656b"
  night: "#151516"
  night-surface: "#1e1e20"
  night-well: "#252528"
  night-ink: "#f1f1f2"
typography:
  display:
    fontFamily: "SF Pro Display, -apple-system, system-ui, sans-serif"
    fontSize: "clamp(50px, 6.6vw, 96px)"
    fontWeight: 700
    lineHeight: 0.98
    letterSpacing: "-0.045em"
  headline:
    fontFamily: "SF Pro Display, -apple-system, system-ui, sans-serif"
    fontSize: "clamp(32px, 3.6vw, 48px)"
    fontWeight: 700
    lineHeight: 1.06
    letterSpacing: "-0.035em"
  title:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "14.5px"
    fontWeight: 400
    lineHeight: 1.45
  body-small:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
  timecode:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "11px"
    fontWeight: 400
    fontFeature: "tnum"
  clock:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "13px"
    fontWeight: 500
    fontFeature: "tnum"
rounded:
  hairline: "2px"
  lane: "3px"
  well: "4px"
  pill: "7px"
  row: "8px"
  card: "10px"
  panel: "14px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "10px"
  lg: "14px"
  xl: "20px"
components:
  pill-toggle:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body-small}"
    rounded: "{rounded.pill}"
    padding: "0 10px"
    height: "26px"
  pill-toggle-on:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent}"
    rounded: "{rounded.pill}"
    padding: "0 10px"
    height: "26px"
  play-button:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    size: "38px"
  mark-chip:
    backgroundColor: "{colors.mark-amber}"
    textColor: "{colors.mark-ink}"
    rounded: "{rounded.well}"
    height: "18px"
  speaker-lane-block:
    backgroundColor: "{colors.voice-violet}"
    rounded: "{rounded.lane}"
    height: "14px"
  transcript-paragraph:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    padding: "9px 10px"
  transcript-paragraph-playing:
    backgroundColor: "{colors.accent}"
    rounded: "{rounded.row}"
    padding: "9px 10px"
  record-stop-button:
    backgroundColor: "{colors.record-red}"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.pill}"
    height: "28px"
---

# Design System: Murmur

## Overview

**Creative North Star: "The Score"**

Murmur reads like a musical score. Time runs left to right; every voice gets its own staff (a lane) in its own colour; the transcript underneath is the libretto, with the word being sung lit up. The waveform, lanes, marks and playhead are the notation. Everything else on screen is the music stand, and a good stand is not looked at.

That makes the system deliberately two-layered. The chrome is stock macOS: system font, system accent, system materials, separator hairlines, 26 pt controls, and toolbar items where a Mac user expects them. The identity lives entirely in the notation: the speaker colours, the amber of a mark, the rhythm of rounded waveform bars and lane blocks, and monospaced timecodes that line up in columns. Density is that of a pro tool (11–13 pt UI, 14.5 pt reading text) with generous breathing room only around the transcript, which is where people actually read.

Depth follows macOS 26: chrome and floating things are layered glass, content is flat. The system toolbar is Liquid Glass, and so is everything that floats: the recorder panel and strip, the processing capsule, the jump-to-now pill and toasts (`.glassEffect`). The timeline and transcript stay flat and opaque so the notation never sits on a blur; even inside the recorder's glass, the live transcript sits on the opaque window colour.

**Key Characteristics:**
- Native macOS chrome; identity carried only by the notation (voices, marks, playhead).
- Three colour jobs, never mixed: voices, amber marks, system accent.
- Flat, opaque content; layered glass only for chrome and things that float.
- Monospaced, tabular timecodes everywhere a time is shown.
- Light and dark are equal citizens; every colour has a tested pair.

## Colors

A neutral paper-and-ink ground on which only three things may carry hue: the voices, the marks and the system accent.

### Primary
- **Voice colours** (`voice-violet`, `voice-orange`, `voice-teal` in the default Vivid scheme): one per speaker, applied to the speaker's name in the transcript, their lane blocks, their waveform bars, the dot beside their name and their talk-time bar. Nine user-selectable schemes (Vivid, Ink, Carbon, Tableau, Slate, Calm, Color-blind safe, High contrast, Earth) live in `Packages/MurmurCore/Sources/MurmurCore/SpeakerPalettes.swift` as light/dark sRGB pairs; Vivid uses the system purple, orange, teal, pink, green and so on. Speaker colour always comes from `Palette.speaker(index)`, never a literal.

### Secondary
- **Mark Amber** (`mark-amber` / `mark-amber-dark`): the colour of a kept moment. Mark chips on the timeline (18% fill, 1 pt amber stroke), the square mark swatch (2–3 pt corners), the pending selection while a mark is open, and the "Marked" tag in the live transcript. Text on amber uses **Mark Ink** (`mark-ink` / `mark-ink-dark`).

### Tertiary
- **System Accent** (`accent` / `accent-dark`, shown as macOS's default blue): follows the user's macOS accent colour and is never overridden. It fills the play button, the selection on the timeline and its edge handles, the overview's viewport frame, the active word highlight (28% opacity), the playing paragraph (10%; 20% when also selected) and the "on" state of pill toggles (12% fill plus accent stroke and text).
- **Record Red** (`record-red`, the system red): recording only. The recording dot and the Stop button; beyond that, only the system's own destructive confirmations.

### Neutral
- **Paper** (`paper`) / **Night** (`night`): page ground on the website; in the app, the window background is the system's.
- **Surface** (`surface` / `night-surface`): control and card fill (`controlBackgroundColor` in the app).
- **Well** (`well` / `night-well`): the empty track behind each speaker lane and the overview strip, keycap fills and tag fills (`quaternaryLabelColor` at 50% in the app).
- **Ink** (`ink`, `ink-secondary`, `ink-tertiary`): primary, secondary and tertiary text; in the app these are `.primary`, `.secondary` and `tertiaryLabelColor`. Silence in the waveform is drawn in tertiary ink.
- Hairlines are the system separator colour (`rgba(20,20,30,0.1)` light and `rgba(255,255,255,0.09)` dark on the site).

### Named Rules
**The Three Jobs Rule.** Hue means exactly one of three things: a voice, a mark, or the system accent. A new feature that wants colour picks one of those jobs or stays neutral; warnings use the system orange and yellow at 8–10% tint, and search hits use yellow at 45%.

**The Tested Pair Rule.** Every speaker colour ships as a light/dark pair that clears 3:1 against both window backgrounds and is at least 0.06 apart from its siblings in OKLab. The tests in `PaletteTests.swift` enforce it; a new scheme that fails them does not ship.

**The Not-Colour-Alone Rule.** A voice is always identified by more than its colour: its name, its lane position, and in High contrast and Slate, diagonal hatching on every other speaker's lane blocks.

## Typography

**Display Font:** SF Pro Display (website headlines only)
**Body Font:** SF Pro Text (system font, `.system(size:)`)
**Label/Mono Font:** SF Mono (`design: .monospaced`) for every timecode and duration

**Character:** One family, used the way macOS uses it: small, exact and unshowy in the app, with the only large type being the website's tightly tracked headlines. Monospaced digits make time readable as a column.

### Hierarchy
- **Display** (700, `clamp(50px, 6.6vw, 96px)`, 0.98, −0.045em): website hero only ("Who said what, when.").
- **Headline** (700, `clamp(32px, 3.6vw, 48px)`, 1.06, −0.035em): website section headings only.
- **Title** (600, 13 pt): section headers in the app ("Transcript", "Summary", "Speakers", "Marks", "Live transcript"), via `SectionHeader`.
- **Body** (400, 14.5 pt, 3 pt extra line spacing): transcript words, the thing people read. Fillers are italic and secondary; redacted spans are 500 weight.
- **Body small** (400, 12–12.5 pt): sidebar text, summaries, pill and button labels (pills at 12 pt, 500).
- **Label** (400, 11 pt, secondary): timeline row labels, hints, metadata lines. Speaker names in transcript gutters are 12 pt 600 in the speaker's colour.
- **Timecode** (SF Mono 400, 10–11 pt, secondary): transcript paragraph times, ruler ticks, mark ranges.
- **Clock** (SF Mono 500, 13 pt in the project window, 15 pt in the compact recorder, 22 pt in the full recorder): the running or playhead time.

### Named Rules
**The Monospaced Time Rule.** Any time, duration or percentage that may change or sit in a column is set in SF Mono or with `monospacedDigit()`. Times never jitter while playing.

**The No Display In The App Rule.** The app has no display type; its largest type is the onboarding title (`.title2`) and the recorder clock. Big type belongs to the website.

## Layout

The project window stacks the score on top and the libretto below: a control bar (play, skip, clock, Enhance on the left; Mark section and zoom on the right), then the timeline (Overview strip 26 pt, Marks row 18 pt, Waveform 110 pt, one 22 pt lane per speaker, ruler 20 pt), then the transcript, with a sidebar on the right holding Video, Summary, Speakers, Marks and Redaction. A fixed 104 pt label column aligns every timeline row's label so the tracks start on the same x. When there are many speakers the lanes scroll rather than growing the window.

Transcript paragraphs are a two-column grid: a speaker-and-time gutter on the left, words on the right, 14 pt between them; rows are padded 9×10 pt with 2 pt between rows. Panels are inset 20 pt horizontally, sidebar cards 12–14 pt. The common spacing steps are 6, 8, 10, 12, 14 and 20 pt; there is no 4/8 grid dogma, the rhythm follows the macOS controls.

The recorder is a 280 pt floating panel that collapses to a single-line strip (timer, latest line, mark, Stop).

The website uses a 1240 px max width, `clamp(20px, 4vw, 48px)` side padding, and a 136 px gutter column for section labels that mirrors the app's timeline label column.

## Elevation & Depth

Content is flat and opaque; chrome and floating things are glass. The timeline, lanes, transcript and sidebar cards sit directly on the window background with hairline separators and tonal wells, no shadows. Chrome and things that float over content are macOS 26 Liquid Glass: the system toolbar, toasts (`.regular`, 8 pt corners), the processing capsule (`.regular`, capsule), the jump-to-now pill (`.regular.interactive()`, capsule) and the recorder panel and strip (`.regular`, 14 pt corners and capsule). Glass draws its own edge and shadow, so these carry no separator stroke and no hand-made drop shadow.

### Shadow Vocabulary
- **Glass** (system-drawn by `.glassEffect`): every floating surface in the app. No custom shadow values.
- **Site showcase** (`0 1px 0 rgba(0,0,0,.04), 0 24px 60px -24px rgba(30,30,50,.28), 0 4px 14px -6px rgba(30,30,50,.12)`): website screenshots and the demo card only.

### Named Rules
**The Opaque Score Rule.** Nothing with a time on it (timeline, lanes, waveform, transcript) ever sits on a translucent material. Glass is for chrome and floating panels only; when a floating panel holds words, as the recorder does, the words get an opaque window-colour region inside the glass.

## Shapes

Small, consistent continuous corners scaled to the element's size: 1–2 pt on waveform bars and mark swatches, 3 pt on lane blocks, 4 pt on wells and keycaps, 7 pt on pill controls, 8 pt on transcript rows and toasts, 10 pt on sidebar cards, 14 pt on the recorder panel; capsules for floating status pills, circles for the play button, Stop, speaker dots and the playhead knob. Borders are 1 pt hairlines in the separator colour; selected states swap the hairline for the accent. Waveform bars are rounded rectangles with a 2 pt gap, so the wave reads as discrete strokes rather than a filled shape.

## Components

### Buttons
- **Pill toggle** (`PillToggle` / `PillStyle`): 26 pt high, 7 pt corners, 10 pt side padding, 12 pt medium label with an optional SF Symbol. Off: control background with a separator hairline. On: accent at 12% with an accent hairline and accent text, and the selected trait for VoiceOver. Pressed: 70% opacity. Used for Enhance, Fillers, Redact, Edit and the language picker.
- **Play button**: 38 pt accent circle with a white 14 pt semibold SF Symbol; the only filled accent button in the window.
- **Segmented zoom control**: minus, span label (12 pt medium, monospaced digits) and plus in one 7 pt-cornered control-background shape with hairline dividers.
- **Stop / Record**: system red, 7 pt corners at 28 pt high in the full recorder, a 28 pt red circle in the strip.
- **Keycaps**: 10 pt semibold rounded-design glyph in a 16 pt box, 4 pt corners, primary at 6% fill with a hairline ("M" next to Mark section).

### Chips
- **Mark chip** (timeline): 4 pt rounded rectangle on the 18 pt marks row, amber at 18% with a 1 pt amber stroke, name in 10 pt semibold Mark Ink. Overlapping marks stack; overflow shows "+N more".
- **Category tag** (redaction list): 10 pt semibold secondary text on a well fill, 4 pt corners.

### Cards / Containers
- **Corner Style:** 10 pt.
- **Background:** control background, or a 8–10% tint of orange or yellow for warnings ("Media missing", "Check the language").
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** separator hairline.
- **Internal Padding:** 12–14 pt.

### Inputs / Fields
- Standard macOS text fields and the toolbar search field ("Search titles and transcripts"). Speaker names are edited in place in rounded fields in the sidebar. No custom field styling.

### Navigation
- Library: a standard `NavigationSplitView` with a 180–210 pt sidebar and a toolbar search. Project window: standard title bar with file name and a metadata subtitle ("Field Notes ep. 14.mp4 · 00:58 · 3 speakers"), copy and share in the toolbar.

### Timeline (signature component)
The score. A row-label column (11 pt secondary) beside stacked tracks: overview strip (whole file, voice-coloured bars at 55%, accent viewport frame on a well), marks row, waveform (voice-coloured rounded bars, full opacity before the playhead, 40% after; dotted tertiary silence), speaker lanes (well track with 3 pt voice blocks, hatched on alternate speakers in High contrast and Slate) and a monospaced ruler. The playhead is a 2 pt primary line with a 10 pt knob. Selections tint with the accent at 12% with 2 pt edges and 6×18 pt grab handles, and turn amber while a mark is pending.

### Transcript paragraph (signature component)
Gutter with the speaker name (12 pt semibold, voice colour) over its start time (11 pt mono, secondary), then the words at 14.5 pt. While playing: words already spoken are primary, words still to come are secondary, the current word gets an accent highlight at 28%, and the row takes an accent tint at 10%. Fillers are italic secondary; redacted spans become bars or soft fills.

### Recorder panel (signature component)
A 14 pt-cornered Liquid Glass panel: the header (dot, clock, shrink and expand) and the footer controls sit on glass, and the live transcript between them sits on the opaque window colour. It holds a recording dot and large monospaced clock, two level meters labelled Me and Others with live mini-waveforms, the live transcript with amber "Marked" tags, and Mark, Pause and Stop at the bottom. A note says it is hidden from screen sharing. It collapses to a strip.

## Do's and Don'ts

### Do:
- **Do** take every speaker colour from the active scheme (`Palette.speaker(index)`) and keep it consistent across name, dot, lane, waveform and talk-time bar.
- **Do** use the system accent (`Color.accentColor`) for playback, selection and "on" states, and let it follow the user's macOS setting.
- **Do** reserve amber (`Palette.mark`, `Palette.markText`) for marks and pending marks.
- **Do** set every time and duration in SF Mono or with monospaced digits.
- **Do** use `.glassEffect` for anything that floats, and the separator colour for hairlines, instead of custom translucency, strokes or shadows.
- **Do** ship every new colour as a light/dark pair, and add any new speaker scheme to `SpeakerPalettes` so the contrast and distance tests cover it.
- **Do** use the stock control (`PillToggle`, `SectionHeader`, `Toast`) before inventing a new one.

### Don't:
- **Don't** add a custom brand accent; the accent is the system's (PRODUCT.md, PLAN.md).
- **Don't** use a speaker colour for anything that isn't that speaker, or amber for anything that isn't a mark.
- **Don't** use system red outside recording and destructive confirmation.
- **Don't** put the timeline or transcript on a translucent material.
- **Don't** let a voice be identifiable by colour alone; keep the name and lane, and hatch where the scheme asks for it.
- **Don't** add display-size type, gradients or decorative shadows inside the app.
