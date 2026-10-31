import AppKit
import MurmurCore
import SwiftUI

struct TranscriptView: View {
    @Bindable var session: ProjectSession
    /// Paragraph ids currently on screen, to know when the current line has scrolled away.
    @State private var onScreen: Set<Int> = []
    @FocusState private var searchFocused: Bool

    var visible: [Paragraph] {
        let q = session.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return session.paragraphs }
        return session.paragraphs.filter { p in
            Merge.join(session.project.words[p.range]).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.project.words.isEmpty {
                ContentUnavailableView {
                    Label(session.project.status == .failed ? "Not transcribed" : "No words yet", systemImage: "text.bubble")
                } description: {
                    Text(session.project.failure ?? "The transcript appears here once processing finishes.")
                } actions: {
                    if session.project.status == .failed && !session.mediaMissing {
                        Button("Transcribe") { session.retranscribe() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Text("Transcript").font(.system(size: 13, weight: .semibold))
            LanguageMenu(session: session, title: languageName(session.project.language))
                .menuStyle(.button)
                .buttonStyle(PillStyle())
                .fixedSize()
            Text(session.editing ? "Type to fix words · press Return to keep a change · edited words are re-timed"
                                 : "Click a line to jump · shift-click to extend the selection")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            PillToggle(title: session.project.settings.showFillers ? "Fillers shown" : "Fillers hidden",
                       systemImage: session.project.settings.showFillers ? "ellipsis.bubble" : "ellipsis.bubble.fill",
                       isOn: Binding(get: { session.project.settings.showFillers },
                                     set: { v in session.update(v ? "Show Fillers" : "Hide Fillers") { $0.settings.showFillers = v } }))
                .help("Show or hide um, uh and hmm in the transcript")
            PillToggle(title: "Redact", systemImage: session.isFindingDetails ? "hourglass" : "eye.slash",
                       isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) }))
                .help("Hide names, phone numbers, addresses and other personal details in the transcript, copies, exports and clips (Redact)")
            PillToggle(title: session.editing ? "Done" : "Edit", systemImage: "pencil", isOn: $session.editing)
            TextField("Search", text: $session.search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($searchFocused)
                .onChange(of: session.findRequest) { _, _ in searchFocused = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    var list: some View {
        let active = session.activeParagraph
        let activeWord = active.flatMap { p in
            session.project.words[p.range].lastIndex { $0.start <= session.player.time + 0.02 }
                .map { $0 - p.range.lowerBound } ?? 0
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { p in
                        ParagraphRow(
                            paragraph: p,
                            words: Array(session.project.words[p.range]),
                            name: session.project.name(of: p.speaker),
                            colorIndex: session.color(of: p.speaker),
                            activeWord: p.id == active?.id ? activeWord : nil,
                            inSelection: session.selection.map { p.end > $0.lowerBound && p.start < $0.upperBound } ?? false,
                            showFillers: session.project.settings.showFillers,
                            editing: session.editing,
                            query: session.search,
                            hidden: session.hiddenSpans.filter { $0.end > p.start && $0.start < p.end },
                            redactionStyle: AppSettings.redactionStyleValue,
                            speakers: session.project.speakers,
                            session: session
                        )
                        .equatable()
                        .id(p.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .scrollTargetLayout()
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { ids in onScreen = Set(ids) }
            .onChange(of: active?.id) { _, id in
                guard let id, session.player.isPlaying, !session.editing, onScreen.isEmpty || onScreen.contains(lastActive(before: id)) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: session.jumpRequest) { _, _ in
                guard let id = session.activeParagraph?.id ?? session.paragraphs.last(where: { $0.start <= session.player.time })?.id else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if let current = currentParagraphID, !onScreen.isEmpty, !onScreen.contains(current) {
                    Button { session.jumpRequest += 1 } label: {
                        HStack(spacing: 6) {
                            Image(systemName: currentIsBelow(current) ? "arrow.down" : "arrow.up")
                            Text("Back to \(Timecode.short(session.player.time))")
                            KeyCap(key: "⌘J")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .help("Scroll back to what's playing (⌘J)")
                }
            }
            .animation(.easeOut(duration: 0.2), value: currentParagraphID.map { onScreen.contains($0) })
        }
    }
}

extension TranscriptView {
    /// The paragraph at the playhead, or the last one before it during a pause in speech.
    var currentParagraphID: Int? {
        session.activeParagraph?.id ?? session.paragraphs.last(where: { $0.start <= session.player.time })?.id
    }

    func currentIsBelow(_ id: Int) -> Bool { (onScreen.max() ?? 0) < id }

    /// Auto-scroll only follows while the line that was playing is still on screen.
    func lastActive(before id: Int) -> Int {
        session.paragraphs.last(where: { $0.id < id })?.id ?? id
    }
}

struct ParagraphRow: View, Equatable {
    let paragraph: Paragraph
    let words: [Word]
    let name: String
    let colorIndex: Int
    let activeWord: Int?
    let inSelection: Bool
    let showFillers: Bool
    let editing: Bool
    let query: String
    let hidden: [RedactedSpan]
    let redactionStyle: RedactionStyle
    let speakers: [Speaker]
    let session: ProjectSession

    @State private var draft = ""
    @FocusState private var focused: Bool

    static func == (a: ParagraphRow, b: ParagraphRow) -> Bool {
        a.paragraph == b.paragraph && a.words == b.words && a.name == b.name && a.colorIndex == b.colorIndex
            && a.activeWord == b.activeWord && a.inSelection == b.inSelection && a.showFillers == b.showFillers
            && a.editing == b.editing && a.query == b.query && a.speakers == b.speakers
            && a.hidden == b.hidden && a.redactionStyle == b.redactionStyle
    }

    var isActive: Bool { activeWord != nil }
    var color: Color { Palette.speaker(colorIndex) }

    var background: Color {
        switch (isActive, inSelection) {
        case (true, true): Color.accentColor.opacity(0.2)
        case (false, true): Color.accentColor.opacity(0.1)
        case (true, false): Color.primary.opacity(0.05)
        default: .clear
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    Picker("Speaker", selection: Binding(get: { paragraph.speaker },
                                                         set: { session.reassign(paragraph, to: $0) })) {
                        ForEach(speakers) { s in Text(s.displayName).tag(s.id) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 110)
                } else {
                    Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(color).lineLimit(1)
                }
                Text(Timecode.short(paragraph.start))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: editing ? 112 : 96, alignment: .leading)

            if editing {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
                    .focused($focused)
                    .onAppear { draft = plainText }
                    .onChange(of: words) { _, _ in if !focused { draft = plainText } }
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else {
                Text(attributed)
                    .font(.system(size: 14.5))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            if NSEvent.modifierFlags.contains(.shift) { session.extendSelection(to: paragraph) }
            else { session.player.seek(to: paragraph.start + 0.01) }
        }
        .contextMenu {
            Button("Play This Paragraph") { session.player.play(from: paragraph.start, to: paragraph.end) }
            Button("Select This Paragraph") { session.select(paragraph.start...paragraph.end) }
            Button("Copy This Paragraph") {
                session.copy(sections: [TranscriptSection(start: paragraph.start, end: paragraph.end)], what: "paragraph")
            }
            Divider()
            Menu("Assign to") {
                ForEach(speakers) { s in Button(s.displayName) { session.reassign(paragraph, to: s.id) } }
            }
            Button("Make a New Speaker") { session.newSpeaker(from: paragraph) }
            if !hidden.isEmpty {
                Divider()
                Button("Show Hidden Details Here") { hidden.forEach(session.toggleReveal) }
            }
        }
    }

    var plainText: String { Merge.join(words) }

    func commit() {
        session.replaceText(of: paragraph, with: draft)
    }

    var attributed: AttributedString {
        var out = AttributedString()
        var previous: Character?
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var lastSpan: RedactedSpan?
        for (i, word) in words.enumerated() {
            if word.isFiller && !showFillers { continue }
            if let span = Redactor.span(for: word, in: hidden) {
                defer { lastSpan = span }
                if span == lastSpan { continue }
                if !out.characters.isEmpty { out += AttributedString(" ") }
                var piece = AttributedString(Redactor.replacement(for: span, style: redactionStyle))
                piece.foregroundColor = redactionStyle == .bars ? Color.primary : Color.secondary
                piece.backgroundColor = Color.primary.opacity(redactionStyle == .bars ? 0.85 : 0.08)
                piece.font = .system(size: 14.5, weight: .medium)
                out += piece
                previous = "x"
                continue
            }
            lastSpan = nil
            if let previous, let first = word.text.first, !(Merge.isUnspaced(previous) && Merge.isUnspaced(first)) {
                out += AttributedString(" ")
            }
            previous = word.text.last
            var piece = AttributedString(word.text)
            if let activeWord {
                if i == activeWord { piece.backgroundColor = Color.accentColor.opacity(0.28) }
                piece.foregroundColor = i <= activeWord ? Color.primary : Color.secondary
            } else {
                piece.foregroundColor = Color.primary.opacity(0.88)
            }
            if word.isFiller {
                piece.foregroundColor = Color.secondary
                piece.font = .system(size: 14.5).italic()
            }
            if !q.isEmpty && word.text.lowercased().contains(q) { piece.backgroundColor = Color.yellow.opacity(0.45) }
            if word.edited && editing { piece.underlineStyle = .single }
            out += piece
        }
        return out
    }
}
