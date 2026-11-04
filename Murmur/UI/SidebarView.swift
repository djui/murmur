import AVKit
import MurmurCore
import SwiftUI

struct SidebarView: View {
    @Bindable var session: ProjectSession
    @AppStorage(AppSettings.showSummary) private var showSummary = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if session.project.media?.hasVideo == true && !session.mediaMissing {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(
                            title: "Video",
                            expanded: Binding(get: { session.project.settings.showVideo }, set: { _ in session.toggleVideo() }),
                            help: session.project.settings.showVideo ? "Hide the video" : "Show the video")
                        if session.project.settings.showVideo, let problem = session.player.videoProblem {
                            Text(problem).font(.system(size: 12)).foregroundStyle(.secondary)
                        } else if session.project.settings.showVideo {
                            VideoPanel(player: session.player.player, time: session.player.time)
                        }
                    }
                }
                if let warning = session.project.languageWarning { WarningCard(text: warning, session: session) }
                if let summary = session.project.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Summary", expanded: $showSummary, trailing: AnyView(Text("Apple Intelligence").font(.system(size: 11)).foregroundStyle(.secondary)))
                        if showSummary { Text(summary).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.85)).textSelection(.enabled) }
                    }
                }
                SpeakersSection(session: session)
                MarksSection(session: session)
                NotesSection(session: session)
                if session.isRedacting { RedactionSection(session: session) }
                SelectionSection(session: session)
                InfoSection(session: session)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}

struct VideoPanel: NSViewRepresentable {
    let player: AVPlayer
    let time: Double

    /// Shows the picture only: the pointer passes through, so hovering, scrolling or swiping over it
    /// never scrubs, and scrolls reach the sidebar.
    final class PassiveView: AVPlayerView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = PassiveView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        let w = proposal.width ?? 280
        return CGSize(width: w, height: w * 9 / 16)
    }
}

struct WarningCard: View {
    let text: String
    let session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Check the language", systemImage: "character.bubble").font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            LanguageMenu(session: session, title: "Transcribe Again As…")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
    }
}

struct SpeakersSection: View {
    @Bindable var session: ProjectSession
    @AppStorage(AppSettings.showSpeakers) private var expanded = true
    /// The speaker being dragged onto another, to merge them.
    @State private var dragging: Int?

    var body: some View {
        let talk = session.project.talkTime
        let total = max(0.001, talk.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Speakers", expanded: $expanded, trailing: session.project.speakers.count < 2 ? nil : AnyView(
                Text("Drag one onto another to merge").font(.system(size: 11)).foregroundStyle(.secondary)))
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.project.speakers) { speaker in
                        SpeakerRow(session: session, speaker: speaker, talk: talk[speaker.id] ?? 0, total: total, dragging: $dragging)
                    }
                }
            }
        }
    }
}

/// One speaker: dot, name, talk time and share. Drag it onto another row to merge it there, or use
/// "Merge into" while the pointer is over it.
struct SpeakerRow: View {
    @Bindable var session: ProjectSession
    let speaker: Speaker
    let talk: Double
    let total: Double
    @Binding var dragging: Int?
    @State private var hovering = false
    @State private var targeted = false

    var others: [Speaker] { session.project.speakers.filter { $0.id != speaker.id } }
    /// Another speaker is being dragged over this one.
    var isDropTarget: Bool { targeted && dragging != nil && dragging != speaker.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SpeakerDot(index: session.color(of: speaker.id), size: 10)
                SpeakerNameField(speaker: speaker, session: session)
                if !others.isEmpty {
                    mergeMenu
                        .opacity(hovering || isDropTarget ? 1 : 0)
                }
                Text("\(Timecode.short(talk)) \(Int((talk / total * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.well)
                    Capsule().fill(Palette.speaker(session.color(of: speaker.id)))
                        .frame(width: geo.size.width * CGFloat(talk / total))
                }
            }
            .frame(height: 4)
            .padding(.leading, 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isDropTarget ? Color.accentColor.opacity(0.14) : hovering ? Palette.well.opacity(0.6) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 2 : 0))
        .overlay(alignment: .topTrailing) {
            if isDropTarget, let from = dragging {
                Text("Merge \(session.project.name(of: from)) into \(speaker.displayName)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: -8, y: -10)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag {
            dragging = speaker.id
            return NSItemProvider(object: "\(speaker.id)" as NSString)
        } preview: {
            HStack(spacing: 6) {
                SpeakerDot(index: session.color(of: speaker.id), size: 10)
                Text(speaker.displayName).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
        .onDrop(of: [.text], isTargeted: $targeted) { _ in
            defer { dragging = nil }
            guard let from = dragging, from != speaker.id else { return false }
            withAnimation(.snappy(duration: 0.2)) { session.merge(from, into: speaker.id) }
            return true
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .help(others.isEmpty ? "" : "Drag onto another speaker to merge, or use Merge into")
    }

    var mergeMenu: some View {
        Menu {
            Section("Merge \(speaker.displayName) into") {
                ForEach(others) { into in
                    Button(into.displayName) { withAnimation(.snappy(duration: 0.2)) { session.merge(speaker.id, into: into.id) } }
                }
            }
        } label: {
            Label("Merge into", systemImage: "arrow.turn.down.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.system(size: 11.5))
        .help("Merge \(speaker.displayName) into another speaker")
        .accessibilityLabel("Merge \(speaker.displayName) into")
    }
}

/// What was taken off the Me track as the speakers' echo, with a way to see it and put any of it back.
struct EchoRemovedRow: View {
    @Bindable var session: ProjectSession
    let spans: [EchoSpan]

    var body: some View {
        let seconds = spans.reduce(0) { $0 + max(0, $1.end - $1.start) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Echo removed").font(.system(size: 12, weight: .medium))
                Text("\(spans.count) \(spans.count == 1 ? "span" : "spans") · \(Timecode.short(seconds))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button(session.showEcho ? "Hide" : "Show") { session.showEcho.toggle() }
                    .buttonStyle(.link).font(.system(size: 12))
            }
            .help("Words the microphone picked up from your speakers, taken out of what you said")
            if session.showEcho {
                ForEach(spans) { span in
                    HStack(spacing: 8) {
                        Button(Timecode.short(span.start)) { session.player.seek(to: span.start) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Text(Merge.join(span.words)).font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button { session.player.play(from: span.start, to: span.end) } label: { Image(systemName: "play.fill") }
                            .buttonStyle(.borderless).help("Play")
                        Button("Restore") { session.restoreEcho(span.id) }
                            .buttonStyle(.borderless).font(.system(size: 11))
                            .help("Put these words back as yours")
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Commits the name when editing ends, so typing doesn't create an undo step per key.
struct SpeakerNameField: View {
    let speaker: Speaker
    let session: ProjectSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(speaker.isMe ? "Me" : "Speaker \(speaker.id + 1)", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .medium))
            .focused($focused)
            .onAppear { text = speaker.name }
            .onChange(of: speaker.name) { _, v in if !focused { text = v } }
            .onSubmit { session.rename(speaker: speaker.id, to: text) }
            .onChange(of: focused) { _, f in if !f { session.rename(speaker: speaker.id, to: text) } }
            .accessibilityLabel("Name for speaker \(speaker.id + 1)")
    }
}

/// "press M", or a pointer to the button when marking has no single key.
@MainActor var pressMark: String {
    ShortcutStore.shared.map.key(for: .markSection).map { "press \($0.symbol)" } ?? "click Mark section"
}

struct MarksSection: View {
    @Bindable var session: ProjectSession
    @AppStorage(AppSettings.hasMarked) private var hasMarked = false
    @AppStorage(AppSettings.showMarks) private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Marks", expanded: $expanded, trailing: AnyView(
                Button("Export all…") { session.showExport = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(session.project.marks.isEmpty)))
            if expanded { marks }
        }
    }

    @ViewBuilder var marks: some View {
        if session.project.marks.isEmpty {
            Text(hasMarked ? "No marks yet." : "Select a section and \(pressMark) to keep it as a named mark.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ForEach(session.project.marks) { mark in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.mark).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    MarkNameField(mark: mark, session: session)
                    Button("\(Timecode.short(mark.start)) – \(Timecode.short(mark.end)) · \(Timecode.short(mark.duration))") {
                        session.select(mark.start...mark.end)
                        session.player.seek(to: mark.start)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button { session.player.play(from: mark.start, to: mark.end) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Play mark")
                Button { session.copy(mark: mark) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy mark text")
                Button { session.remove(mark: mark.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Remove mark")
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// Notes written while recording or listening, with a field to add one at the playhead.
struct NotesSection: View {
    @Bindable var session: ProjectSession
    @AppStorage(AppSettings.showNotes) private var expanded = true
    @State private var draft = ""
    /// The playhead when the draft's first letter was typed.
    @State private var draftTime: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes", expanded: $expanded, trailing: session.notes.isEmpty ? nil : AnyView(
                Text("\(session.notes.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)))
            if expanded {
                ForEach(session.notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button(Timecode.short(note.time)) {
                            session.player.seek(to: note.time)
                            session.jumpRequest += 1
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.markText)
                        .help("Go to \(Timecode.short(note.time))")
                        NoteTextField(note: note, session: session)
                        Button { session.remove(note: note.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove note")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Timecode.short(draftTime ?? session.player.time))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                    TextField("Add a note at the playhead", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .lineLimit(1...4)
                        .onChange(of: draft) { old, new in
                            if old.isEmpty && !new.isEmpty { draftTime = session.player.time }
                            if new.isEmpty { draftTime = nil }
                        }
                        .onSubmit {
                            session.addNote(draft, at: draftTime ?? session.player.time)
                            draft = ""
                            draftTime = nil
                        }
                }
            }
        }
    }
}

struct NoteTextField: View {
    let note: Note
    let session: ProjectSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Note", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .lineLimit(1...6)
            .focused($focused)
            .onAppear { text = note.text }
            .onChange(of: note.text) { _, v in if !focused { text = v } }
            .onSubmit { session.edit(note: note.id, to: text) }
            .onChange(of: focused) { _, f in if !f { session.edit(note: note.id, to: text) } }
    }
}

struct MarkNameField: View {
    let mark: Mark
    let session: ProjectSession
    /// With a field border, where the name is the thing being edited (the timeline popover).
    var bordered = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        styled(TextField("Mark", text: $text))
            .font(.system(size: bordered ? 13 : 12.5, weight: .medium))
            .foregroundStyle(.primary)
            .focused($focused)
            .onAppear { text = mark.name }
            .onChange(of: mark.name) { _, v in if !focused { text = v } }
            .onSubmit { session.rename(mark: mark.id, to: text) }
            .onChange(of: focused) { _, f in if !f { session.rename(mark: mark.id, to: text) } }
    }

    @ViewBuilder func styled(_ field: TextField<Text>) -> some View {
        if bordered { field.textFieldStyle(.roundedBorder) } else { field.textFieldStyle(.plain) }
    }
}

struct RedactionSection: View {
    let session: ProjectSession
    @AppStorage(AppSettings.showPersonalDetails) private var expanded = true

    var body: some View {
        let spans = session.project.redactions ?? []
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Personal details", expanded: $expanded, trailing: AnyView(
                Text("\(spans.filter { !$0.revealed }.count) hidden").font(.system(size: 11)).foregroundStyle(.secondary)))
            if expanded { details(spans) }
        }
    }

    @ViewBuilder func details(_ spans: [RedactedSpan]) -> some View {
        if spans.isEmpty {
            Text(session.isFindingDetails ? "Looking for names, numbers and addresses…" : "None found.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
            HStack(spacing: 8) {
                Text(span.category).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).background(RoundedRectangle(cornerRadius: 4).fill(Palette.well))
                Text(span.revealed ? span.original : Redactor.replacement(for: span, style: AppSettings.redactionStyleValue))
                    .font(.system(size: 12.5)).lineLimit(1)
                Spacer()
                Button(Timecode.short(span.start)) { session.player.seek(to: span.start) }
                    .buttonStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Button { session.toggleReveal(span) } label: { Image(systemName: span.revealed ? "eye" : "eye.slash") }
                    .buttonStyle(.borderless)
                    .help(span.revealed ? "Hide this detail again" : "Show this detail everywhere")
            }
        }
    }
}

struct SelectionSection: View {
    @Bindable var session: ProjectSession
    @AppStorage(AppSettings.hasSelected) private var hasSelected = false

    var body: some View {
        // After the first selection the section only appears while something is selected.
        if session.selection != nil || !hasSelected { content }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Selection")
            if let sel = session.selection {
                let range = Merge.indices(of: session.project.words, from: sel.lowerBound, to: sel.upperBound)
                let words = session.project.words[range].filter { !$0.isFiller }.count
                let paragraphs = session.paragraphs.filter { $0.end > sel.lowerBound && $0.start < sel.upperBound }.count
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Timecode.precise(sel.lowerBound))  →  \(Timecode.precise(sel.upperBound))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text("\(Timecode.precise(sel.upperBound - sel.lowerBound)) long · \(paragraphs) \(paragraphs == 1 ? "paragraph" : "paragraphs") · \(words) words")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Copy text") { session.copySelection() }.buttonStyle(.borderedProminent)
                        Button("Save as mark") { session.addMark() }
                        Button("Clear") { session.selection = nil }.buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            } else {
                Text("Drag across the waveform, or shift-click lines, to select. To mark a section, \(pressMark) at its start and again at its end. Cuts snap to whole words.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct InfoSection: View {
    let session: ProjectSession
    @AppStorage(AppSettings.showProcessingInfo) private var expanded = false

    var body: some View {
        let p = session.project
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Processed on this Mac", expanded: $expanded,
                help: expanded ? "Hide how this project was processed" : "Show how this project was processed")
            if expanded {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Language", "\(languageName(p.language))" + (p.languageConfidence.map { " · \(Int($0 * 100))%" } ?? ""))
                    row("Words", "\(p.words.filter { !$0.isFiller }.count) · \(p.transcriber == "apple" ? "Apple" : "Voz")")
                    row("Speakers", "\(p.speakers.count) · Who")
                    row("Fillers", "\(p.words.filter(\.isFiller).count) · Uhm")
                }
                .font(.system(size: 12))
            }
        }
    }

    func row(_ a: String, _ b: String) -> some View {
        GridRow {
            Text(a).foregroundStyle(.secondary)
            Text(b)
        }
    }
}
