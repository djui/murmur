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
                    Text(session.project.failure ?? (session.isProcessing
                        ? "Words appear here as they’re transcribed. You can listen already."
                        : "The transcript appears here once processing finishes."))
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

    /// Title and language, the two view toggles, the edit mode and search. How to use the lines
    /// lives in the list's tooltip; only edit mode, which changes what keys do, says so inline.
    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Transcript").font(.system(size: 13, weight: .semibold))
                LanguageMenu(session: session, title: languageName(session.project.language))
                    .menuStyle(.button)
                    .buttonStyle(PillStyle())
                    .fixedSize()
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    PillToggle(title: "Fillers", systemImage: "ellipsis.bubble",
                               isOn: Binding(get: { session.project.settings.showFillers },
                                             set: { v in session.update(v ? "Show Fillers" : "Hide Fillers") { $0.settings.showFillers = v } }))
                        .help(session.project.settings.showFillers ? "Um, uh and hmm are shown, faded. Click to hide them"
                                                                   : "Um, uh and hmm are hidden. Click to show them")
                    PillToggle(title: "Redact", systemImage: session.isFindingDetails ? "hourglass" : "eye.slash",
                               isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) }))
                        .help("Hide names, phone numbers, addresses and other personal details in the transcript, copies, exports and clips (Redact)")
                        .disabled(session.isProcessing)
                }
                // The finished transcript replaces the words shown while processing, and edits with them.
                PillToggle(title: session.editing ? "Done" : "Edit", systemImage: "pencil", isOn: $session.editing)
                    .help(session.isProcessing ? "Edit once transcribing is done" : session.editing ? "Stop editing" : "Fix words in place")
                    .disabled(session.isProcessing)
                TextField("Search", text: $session.search, prompt: Text("Search"))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 220)
                    .focused($searchFocused)
                    .onChange(of: session.findRequest) { _, _ in searchFocused = true }
            }
            if session.editing {
                Text("Type to fix words · press Return to keep a change · select words to give them to another speaker")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.editing)
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
                            before: neighbour(of: p, offset: -1),
                            after: neighbour(of: p, offset: 1),
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
            .help(session.editing ? "" : "Click a line to jump · shift-click to extend the selection")
        }
    }
}

extension TranscriptView {
    /// The paragraph at the playhead, or the last one before it during a pause in speech.
    var currentParagraphID: Int? {
        session.activeParagraph?.id ?? session.paragraphs.last(where: { $0.start <= session.player.time })?.id
    }

    /// The speaker of the line before (-1) or after (1), to suggest when giving words away.
    func neighbour(of paragraph: Paragraph, offset: Int) -> Int? {
        guard let i = session.paragraphs.firstIndex(where: { $0.id == paragraph.id }),
              session.paragraphs.indices.contains(i + offset) else { return nil }
        return session.paragraphs[i + offset].speaker
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
    let before: Int?
    let after: Int?
    let session: ProjectSession

    @State private var draft = ""
    @State private var textSelection: TextSelection?
    /// Selected characters in the read-only text, outside Edit mode.
    @State private var viewSelection: Range<Int>?
    @FocusState private var focused: Bool

    static func == (a: ParagraphRow, b: ParagraphRow) -> Bool {
        a.paragraph == b.paragraph && a.words == b.words && a.name == b.name && a.colorIndex == b.colorIndex
            && a.activeWord == b.activeWord && a.inSelection == b.inSelection && a.showFillers == b.showFillers
            && a.editing == b.editing && a.query == b.query && a.speakers == b.speakers
            && a.hidden == b.hidden && a.redactionStyle == b.redactionStyle
            && a.before == b.before && a.after == b.after
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
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $draft, selection: $textSelection, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .lineSpacing(3)
                        .focused($focused)
                        .onAppear { draft = plainText }
                        .onChange(of: words) { old, _ in if !focused || draft == Merge.join(old) { draft = plainText } }
                        .onSubmit { commit() }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit(); textSelection = nil } }
                    if let selected = editedWords { giveBar(selected) }
                }
            } else {
                let text = rendered
                VStack(alignment: .leading, spacing: 8) {
                    SelectableText(text: text.string, selection: $viewSelection,
                                   onClick: { session.player.seek(to: paragraph.start + 0.01) },
                                   onShiftClick: { session.extendSelection(to: paragraph) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let selected = viewSelection.flatMap(text.words(touching:)) { giveBar(selected) }
                }
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

    /// The paragraph's words the Edit-mode text selection touches, as indices into the project's words.
    var editedWords: Range<Int>? {
        guard focused, case .selection(let range)? = textSelection?.indices, !range.isEmpty else { return nil }
        let lo = draft.distance(from: draft.startIndex, to: range.lowerBound)
        let hi = draft.distance(from: draft.startIndex, to: range.upperBound)
        if draft != plainText { return 0..<0 }
        return Editing.words(words, touching: lo..<hi)
            .map { ($0.lowerBound + paragraph.range.lowerBound)..<($0.upperBound + paragraph.range.lowerBound) }
    }

    /// "Give N selected words to …": hands part of the paragraph to another speaker.
    @ViewBuilder func giveBar(_ selected: Range<Int>) -> some View {
        HStack(spacing: 6) {
            if selected.isEmpty {
                Text("Press Return to keep your change, then pick who said the selected words")
            } else {
                Text(selected.count == paragraph.range.count ? "Give this paragraph to"
                                                             : "Give \(selected.count) selected \(selected.count == 1 ? "word" : "words") to")
                let suggested = Editing.suggestedSpeakers(for: selected, in: paragraph, before: before, after: after)
                ForEach(suggested + speakers.map(\.id).filter { $0 != paragraph.speaker && !suggested.contains($0) }, id: \.self) { id in
                    Button { give { session.reassign(words: selected, to: id) } } label: {
                        HStack(spacing: 5) {
                            if suggested.contains(id) {
                                Image(systemName: id == before && selected.lowerBound == paragraph.range.lowerBound ? "arrow.up" : "arrow.down")
                            } else {
                                Circle().fill(Palette.speaker(session.color(of: id))).frame(width: 7, height: 7)
                            }
                            Text(name(of: id))
                        }
                    }
                    .buttonStyle(PillStyle(isOn: suggested.contains(id)))
                    .help(suggested.contains(id) ? "Join \(name(of: id)) on the line \(id == before && selected.lowerBound == paragraph.range.lowerBound ? "before" : "after")"
                                                 : "Give the selected words to \(name(of: id))")
                }
                Button { give { session.newSpeaker(words: selected) } } label: { Label("New Speaker", systemImage: "plus") }
                    .buttonStyle(PillStyle())
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    func name(of id: Int) -> String {
        speakers.first { $0.id == id }?.displayName ?? "Speaker \(id + 1)"
    }

    func give(_ action: () -> Void) {
        textSelection = nil
        viewSelection = nil
        action()
    }

    func commit() {
        session.replaceText(of: paragraph, with: draft)
    }

    /// The paragraph as AppKit text, with which characters show which words.
    var rendered: RenderedParagraph {
        let out = NSMutableAttributedString()
        var pieces: [(chars: Range<Int>, words: Range<Int>)] = []
        var previous: Character?
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var lastSpan: RedactedSpan?
        let base = NSFont.systemFont(ofSize: 14.5)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        func append(_ text: String, _ attributes: [NSAttributedString.Key: Any], word: Int?) {
            let start = out.length
            var attributes = attributes
            attributes[.paragraphStyle] = style
            if attributes[.font] == nil { attributes[.font] = base }
            out.append(NSAttributedString(string: text, attributes: attributes))
            let index = paragraph.range.lowerBound + (word ?? 0)
            if word != nil { pieces.append((start..<out.length, index..<(index + 1))) }
        }
        for (i, word) in words.enumerated() {
            if word.isFiller && !showFillers { continue }
            if let span = Redactor.span(for: word, in: hidden) {
                defer { lastSpan = span }
                if span == lastSpan {
                    // The redaction stands for this word too.
                    if let last = pieces.indices.last { pieces[last].words = pieces[last].words.lowerBound..<(paragraph.range.lowerBound + i + 1) }
                    continue
                }
                if out.length > 0 { append(" ", [:], word: nil) }
                append(Redactor.replacement(for: span, style: redactionStyle), [
                    .foregroundColor: redactionStyle == .bars ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .backgroundColor: NSColor.labelColor.adaptive(alpha: redactionStyle == .bars ? 0.85 : 0.08),
                    .font: NSFont.systemFont(ofSize: 14.5, weight: .medium),
                ], word: i)
                previous = "x"
                continue
            }
            lastSpan = nil
            if let previous, let first = word.text.first, !(Merge.isUnspaced(previous) && Merge.isUnspaced(first)) {
                append(" ", [:], word: nil)
            }
            previous = word.text.last
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let activeWord {
                if i == activeWord { attributes[.backgroundColor] = NSColor.controlAccentColor.adaptive(alpha: 0.28) }
                attributes[.foregroundColor] = i <= activeWord ? NSColor.labelColor : NSColor.secondaryLabelColor
            } else {
                attributes[.foregroundColor] = NSColor.labelColor.adaptive(alpha: 0.88)
            }
            if word.isFiller {
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
                attributes[.font] = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            }
            if !q.isEmpty && word.text.lowercased().contains(q) { attributes[.backgroundColor] = NSColor.systemYellow.adaptive(alpha: 0.45) }
            append(word.text, attributes, word: i)
        }
        return RenderedParagraph(string: out, pieces: pieces)
    }
}

struct RenderedParagraph {
    let string: NSAttributedString
    let pieces: [(chars: Range<Int>, words: Range<Int>)]

    /// The words (project indices) shown by the selected characters; nil if only spaces are selected.
    func words(touching characters: Range<Int>) -> Range<Int>? {
        let touched = pieces.filter { $0.chars.overlaps(characters) }
        guard let first = touched.first, let last = touched.last else { return nil }
        return first.words.lowerBound..<last.words.upperBound
    }
}

extension NSColor {
    /// A see-through system color that still follows light and dark mode. `withAlphaComponent`
    /// alone fixes the color of whichever mode is current, which stays wrong after a switch.
    func adaptive(alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var color = self
            appearance.performAsCurrentDrawingAppearance { color = self.usingColorSpace(.sRGB)?.withAlphaComponent(alpha) ?? self }
            return color
        }
    }
}
