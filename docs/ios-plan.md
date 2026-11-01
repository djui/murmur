# Murmur on iPhone and iPad — plan

Written against `main` at bd78659 (v0.1.22) and Desert Ant SDK 4.2.3. Progress: section 5.

## 1. Goal

An app for iPhone and iPad that does what the Mac app does: open a recording or record one, get a
transcript with speakers on a timeline, mark sections, fix words and speakers, hide personal details and
share the result. Everything runs on the device; nothing is uploaded.

## 2. Decisions

| Topic | Decision |
|---|---|
| Code | One Xcode project. The `MurmurMobile` target (iOS 26, iPhone and iPad) shares the pipeline, models, playback, decoding, clip export and project files with the Mac app; only the UI is its own (`MurmurMobile/`). |
| Models | The same Desert Ant Swift products as the Mac app (Voz, Who, Ear, Align, Tongue, Uhm, Clear, Redact), downloaded into Application Support on first launch (~515 MB). |
| Projects | `.murmur` packages in Documents/Murmur, the same format as the Mac app; visible in the Files app. |
| Media | Copied into Documents/Murmur/Media on import, because a file from Files or another app is only lent to Murmur. The path is re-rooted when the app's container moves (updates, reinstalls). |
| Recording | Microphone only, one track: iOS has no way to record other apps. Everyone in the room is on that track and Who tells them apart afterwards. Live transcript, pause, moment marks, recording continues with the screen locked, interruptions (calls) pause it. |
| Long transcriptions | `BGContinuedProcessingTask`: leaving the app shows the progress in the system UI and lets the work finish. The screen stays on while Murmur is in front and working. |
| Layout | `NavigationSplitView`: library beside the project on iPad, before it on iPhone. iPhone project: video (if any), a waveform strip that opens into speaker lanes ("Show Speakers", closed each time), the transcript, and the playback controls alone in a glass bar at the bottom, so reaching for a button never moves the playhead. iPad: score and player bar on top, inspector beside the transcript. |
| Design | `DESIGN.md` colours and speaker schemes, system type, Liquid Glass controls. Light, dark or system. |

## 3. What changes from the Mac app

| Mac app | iOS | Note |
|---|---|---|
| Two-track meeting recording (mic + other apps) | Microphone only | No system audio capture on iOS. |
| Floating recorder window, ⌥⌘M from any app | Full-screen recorder sheet; bookmark button marks a moment | A Live Activity / Lock Screen control is in Later. |
| Keyboard shortcuts | Touch: tap, drag to scrub, pinch to zoom; hardware keyboard shortcuts in Later | |
| Drag-select on the timeline | Bookmark button at the start and end of a section, or "Mark Paragraph" | |
| Word-level click in the transcript | Tap a paragraph to play from it; long-press for edit, speaker, mark, copy | |
| Vertical timeline, inspector | Sheets | |
| Video clip export | Audio clips only in v1 | `ClipExporter` can do video; needs the export sheet option. |
| Sparkle updates | App Store / TestFlight | |

## 4. Shared code

Moved so both targets compile them: `AppSettings` and `Appearance` (`Murmur/App/AppSettings.swift`),
`StemWriter` (`Murmur/Audio/StemWriter.swift`). `ProjectSession` gains `relocateMedia(to:)` and uses
`UIPasteboard` on iOS; `MediaRef.resolvedURL()` re-roots paths under Documents on iOS. `MurmurCore`
declares iOS 26.

## 5. Progress

### 1. Groundwork
- [x] Desert Ant products build for iOS (Simulator)
- [x] Shared sources compile for iOS; the Mac app is unchanged
- [x] This plan

### 2. App
- [x] Library: projects in Documents/Murmur, open file, delete with confirmation, "Open in Murmur" from other apps
- [x] First launch: model download with progress
- [x] Project: timeline (speaker-coloured waveform, lanes, marks, scrub, pinch zoom), player bar, transcript
      with the current word, follows playback
- [x] Processing view with each step, continued in the background
- [x] Editing: words, change / new speaker, rename / merge speakers, undo and redo
- [x] Marks: bookmark button, mark a paragraph, rename, delete, play, copy
- [x] Hide personal details, show one by one; enhance audio; transcribe again in a chosen language
- [x] Share: every text format and audio clips (bleeped when redacted)
- [x] Settings: appearance, speaker colours, copy format, models
- [x] Recording: live transcript, pause, moment marks, background, interruptions
- [x] App icon

### 3. Checked
- [x] Simulator (iPhone 18 Pro, iPad Pro 13"): model download, import, transcription (sample: English 99%,
      three speakers), playback, recording with a marked moment, transcription of the recording
- [x] UI/UX critique (`/impeccable critique`): 23/40 before, 28/40 after its fixes (frozen playhead, reflowing
      current word, unnamed lanes, accent misuse, recorder states, speaker rename, library status)
- [x] Mac app still builds; MurmurCore's 47 tests pass

### Later, in order of value
- [ ] Run on a device: memory with an hour of audio (increased-memory-limit entitlement if needed), Neural Engine speed
- [x] Live Activity while recording: clock, marks, voices and level on the Lock Screen and in the Dynamic Island,
      with Pause, Mark and Stop
- [ ] Hardware keyboard shortcuts on iPad (`Shortcuts.swift`)
- [x] Player bar at the bottom on iPhone (thumb reach), apart from the score at the top
- [x] Library: search every transcript (button at the top, field at the bottom), Voice Memos' record button
- [x] Playback bar in ink; Current Line points the right way; hide the video from the video itself
- [x] One home per thing: ⋯ holds actions, Project Info holds Enhance, Hide Personal Details and the facts
- [x] A page per speaker with "Same person as…" to merge, opened from the name in the transcript
- [x] Landscape iPhone: video, score and playback on the left, transcript on the right
- [ ] Lane names for VoiceOver on the timeline
- [ ] Recording survives the app being killed (AAC in .m4a is unreadable until closed; write CAF and convert)
- [ ] Video clip export
- [ ] Share extension: send audio from Voice Memos straight to Murmur
- [x] TestFlight: App Store Connect app "Murmur: Who Said What, When" (com.djui.Murmur), internal group
      "Internal" with automatic distribution; `make testflight` archives and uploads
- [ ] App Store release
